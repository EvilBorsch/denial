//! Screenshot capture and region selection.

use super::*;

impl Session<'_, '_> {
    pub(super) fn begin_pending_screenshot_selection(&mut self) -> Result<bool, Box<dyn Error>> {
        let Self {
            events,
            screenshot_manager: manager,
            topology,
            scheduler,
            swapchain,
            scanouts,
            allocator,
            flutter: runtime,
            ..
        } = self;
        let Some(target_output) = events.pending_screenshot_selection.take() else {
            return Ok(false);
        };
        let Some(manager) = manager.as_mut() else {
            warn!("screenshot selection ignored because the writer is unavailable");
            return Ok(false);
        };
        let snapshot = topology.snapshot();
        let atlas =
            AtlasPlan::for_snapshot(&snapshot).ok_or("screenshot preparation has no atlas")?;
        if scheduler
            .framebuffer_index_for_output(target_output, scanouts)
            .is_none()
        {
            warn!(?target_output, "screenshot target output is not powered");
            return Ok(true);
        }
        let output_swapchains = swapchain
            .outputs()
            .ok_or("screenshot selection has no physical output pools")?;
        let modifier = screenshot_buffer_modifier(scheduler, output_swapchains, target_output)?;
        match manager.begin_selection(allocator, target_output, atlas, modifier) {
            Ok(Some(request_id)) => {
                if let Err(error) = runtime.send_screenshot_action(
                    wire::ShellAction::ScreenshotRegion,
                    request_id,
                    None,
                ) {
                    let _ = manager.cancel_selection(runtime, Some(request_id));
                    return Err(error);
                }
            }
            Ok(None) => debug!("ignored repeated screenshot selection shortcut"),
            Err(error) => warn!(%error, "could not allocate screenshot selection buffer"),
        }
        Ok(false)
    }

    pub(super) fn handle_prepared_screenshot(
        &mut self,
        request_id: Option<std::num::NonZeroU64>,
    ) -> Result<bool, Box<dyn Error>> {
        let Self {
            screenshot_manager: manager,
            scheduler,
            scanouts,
            flutter: runtime,
            frame_scheduler,
            ..
        } = self;
        let Some(request_id) = request_id else {
            return Ok(false);
        };
        let Some(manager) = manager.as_mut() else {
            return Ok(false);
        };
        if manager.request_id() != Some(request_id.get()) {
            return Ok(false);
        }
        let Some(target_output) = manager.target_output() else {
            return Err("prepared screenshot lost its target output".into());
        };
        if scheduler
            .framebuffer_index_for_output(target_output, scanouts)
            .is_none()
        {
            let finished = manager.cancel_selection(runtime, Some(request_id.get()))?;
            if let Some(request_id) = finished {
                runtime.send_screenshot_action(
                    wire::ShellAction::ScreenshotDone,
                    request_id,
                    None,
                )?;
            }
            return Ok(true);
        }
        if manager.prepared(request_id.get()) {
            runtime.arm_screenshot_frame(target_output, request_id.get())?;
            frame_scheduler.mark_output_dirty(target_output);
        } else {
            warn!(
                request_id = request_id.get(),
                "ignored stale screenshot preparation"
            );
        }
        Ok(false)
    }

    pub(super) fn handle_cancelled_screenshot(
        &mut self,
        request_id: Option<std::num::NonZeroU64>,
    ) -> Result<(), Box<dyn Error>> {
        let Self {
            screenshot_manager: manager,
            flutter: runtime,
            ..
        } = self;
        let Some(request_id) = request_id else {
            return Ok(());
        };
        let Some(manager) = manager.as_mut() else {
            return Ok(());
        };
        let Some(request_id) = manager.cancel_selection(runtime, Some(request_id.get()))? else {
            return Ok(());
        };
        runtime.send_screenshot_action(wire::ShellAction::ScreenshotDone, request_id, None)?;
        Ok(())
    }

    pub(super) fn handle_screenshot_request(
        &mut self,
        request: Option<flutter_runtime::system_command::ScreenshotRequest>,
    ) -> Result<(), Box<dyn Error>> {
        let Self {
            screenshot_manager: manager,
            renderer,
            allocator,
            topology,
            scheduler,
            swapchain,
            flutter: runtime,
            ..
        } = self;
        let Some(request) = request else {
            return Ok(());
        };
        let Some(manager) = manager.as_mut() else {
            warn!("screenshot request ignored because the writer is unavailable");
            return Ok(());
        };

        if request.request_id.is_none() {
            let snapshot = topology.snapshot();
            let Some(atlas) = AtlasPlan::for_snapshot(&snapshot) else {
                warn!("screenshot capture skipped because the atlas is unavailable");
                return Ok(());
            };
            let output_swapchains = swapchain
                .outputs()
                .ok_or("live screenshot has no physical output pools")?;
            let mut sources = screenshot_composite_sources(scheduler, output_swapchains, &atlas)?;
            let source_output = atlas
                .outputs
                .first()
                .ok_or("live screenshot atlas has no outputs")?
                .id;
            let modifier = screenshot_buffer_modifier(scheduler, output_swapchains, source_output)?;
            match manager.capture_live(renderer, allocator, &atlas, modifier, &mut sources, request)
            {
                // The pixels are copied: feedback the shell shows now is not in them.
                Ok(()) => {
                    runtime.send_shell_action(wire::ShellAction::ScreenshotCaptured, None, None)?
                }
                Err(error) => warn!(%error, "screenshot capture failed"),
            }
            return Ok(());
        }

        let request_id = request
            .request_id
            .expect("checked screenshot request identity")
            .get();
        if manager.request_id() != Some(request_id) {
            return Ok(());
        }
        if let Err(error) = manager.finish_selection(renderer, runtime, request) {
            warn!(%error, request_id, "frozen screenshot capture failed");
        }
        runtime.send_screenshot_action(wire::ShellAction::ScreenshotDone, request_id, None)?;
        Ok(())
    }

    /// Freezes a tagged output batch as soon as its page-flip completion makes
    /// it visible, before another frame can replace it.
    pub(super) fn freeze_prepared_screenshot_frame(&mut self) -> Result<(), Box<dyn Error>> {
        let Self {
            screenshot_manager: manager,
            renderer,
            flutter: runtime,
            topology,
            scheduler,
            swapchain,
            scanouts,
            ..
        } = self;
        let Some(manager) = manager.as_mut() else {
            return Ok(());
        };
        let Some(target_output) = manager.target_output() else {
            return Ok(());
        };
        let Some(request_id) = manager.request_id() else {
            return Ok(());
        };
        if scheduler
            .screenshot_framebuffer_for_output(target_output, request_id, scanouts)
            .is_none()
        {
            return Ok(());
        }

        let snapshot = topology.snapshot();
        let atlas =
            AtlasPlan::for_snapshot(&snapshot).ok_or("prepared screenshot has no desktop atlas")?;
        let mut sources = screenshot_composite_sources(
            scheduler,
            swapchain
                .outputs()
                .ok_or("prepared screenshot has no physical output pools")?,
            &atlas,
        )?;
        let cover = manager.is_cover();
        match manager.capture_prepared_frame(renderer, runtime, target_output, &mut sources) {
            Ok(Some((request_id, texture_id))) if cover => {
                info!(request_id, texture_id, "froze the frame on screen for a presentation switch");
                runtime.send_screenshot_action(
                    wire::ShellAction::PresentationCover,
                    request_id,
                    Some(texture_id),
                )?;
            }
            Ok(Some((request_id, texture_id))) => runtime.send_screenshot_action(
                wire::ShellAction::ScreenshotTextureReady,
                request_id,
                Some(texture_id),
            )?,
            Ok(None) => {}
            Err(error) => {
                warn!(%error, cover, "could not freeze the screenshot selection canvas");
                if let Some(request_id) = manager.cancel_selection(runtime, None)? {
                    let action = if cover {
                        wire::ShellAction::PresentationCover
                    } else {
                        wire::ShellAction::ScreenshotDone
                    };
                    runtime.send_screenshot_action(action, request_id, None)?;
                }
            }
        }
        Ok(())
    }

    /// The shell switches presentations and asks for the frame on screen as
    /// its cover. The next frame of the panel is frozen once it is on screen
    /// (`freeze_prepared_screenshot_frame`), a GPU copy of what was presented:
    /// nothing is drawn again. Without a frozen frame (a screenshot holds the
    /// buffer, the output is off) the shell hears so at once.
    pub(super) fn handle_presentation_cover_request(
        &mut self,
        request: Option<std::num::NonZeroU64>,
    ) -> Result<(), Box<dyn Error>> {
        let Self {
            screenshot_manager: manager,
            topology,
            scheduler,
            swapchain,
            scanouts,
            allocator,
            flutter: runtime,
            frame_scheduler,
            ..
        } = self;
        let Some(request_id) = request.map(std::num::NonZeroU64::get) else {
            return Ok(());
        };
        let begun = (|| -> Result<Option<OutputId>, Box<dyn Error>> {
            let Some(manager) = manager.as_mut() else {
                return Ok(None);
            };
            let snapshot = topology.snapshot();
            let atlas = AtlasPlan::for_snapshot(&snapshot).ok_or("presentation cover has no atlas")?;
            // The switch happens on one screen.
            let [output] = atlas.outputs.as_slice() else {
                return Ok(None);
            };
            let target_output = output.id;
            if scheduler
                .framebuffer_index_for_output(target_output, scanouts)
                .is_none()
            {
                return Ok(None);
            }
            let output_swapchains = swapchain
                .outputs()
                .ok_or("presentation cover has no physical output pools")?;
            let modifier = screenshot_buffer_modifier(scheduler, output_swapchains, target_output)?;
            Ok(manager
                .begin_cover(allocator, target_output, atlas, modifier, request_id)?
                .then_some(target_output))
        })();
        match begun {
            Ok(Some(target_output)) => {
                if let Err(error) = runtime.arm_screenshot_frame(target_output, request_id) {
                    warn!(%error, request_id, "could not arm the presentation cover frame");
                    if let Some(manager) = manager.as_mut() {
                        manager.release_cover(runtime, request_id)?;
                    }
                    runtime.send_screenshot_action(
                        wire::ShellAction::PresentationCover,
                        request_id,
                        None,
                    )?;
                    return Ok(());
                }
                frame_scheduler.mark_output_dirty(target_output);
            }
            Ok(None) => runtime.send_screenshot_action(
                wire::ShellAction::PresentationCover,
                request_id,
                None,
            )?,
            Err(error) => {
                warn!(%error, request_id, "could not prepare a presentation cover");
                runtime.send_screenshot_action(
                    wire::ShellAction::PresentationCover,
                    request_id,
                    None,
                )?;
            }
        }
        Ok(())
    }

    /// The shell's switch is over: its cover's texture and buffer go.
    pub(super) fn handle_presentation_cover_release(
        &mut self,
        request: Option<std::num::NonZeroU64>,
    ) -> Result<(), Box<dyn Error>> {
        let Self {
            screenshot_manager: manager,
            flutter: runtime,
            ..
        } = self;
        if let (Some(request_id), Some(manager)) = (request, manager.as_mut()) {
            manager.release_cover(runtime, request_id.get())?;
        }
        Ok(())
    }

    pub(super) fn cancel_invalid_screenshot_selection(&mut self) -> Result<(), Box<dyn Error>> {
        let Self {
            screenshot_manager: manager,
            flutter: runtime,
            topology,
            scheduler,
            scanouts,
            events,
            ..
        } = self;
        let invalid = manager.as_ref().is_some_and(|manager| {
            manager.request_id().is_some()
                && (events.secure_session_locked()
                    || manager.topology_epoch() != Some(topology.epoch())
                    || manager.target_output().is_some_and(|output| {
                        scheduler
                            .framebuffer_index_for_output(output, scanouts)
                            .is_none()
                    }))
        });
        if invalid {
            cancel_active_screenshot(
                manager,
                runtime,
                true,
                "screenshot canvas is no longer valid",
            )?;
        }
        Ok(())
    }
}
