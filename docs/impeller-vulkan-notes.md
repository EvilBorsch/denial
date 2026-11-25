# Impeller on Vulkan (Turnip): notes for a later track

Parked on 2026-11-25 by the owner's decision; eb20 ships on GLES with the Mesa tile-skip fix.
Nothing here is built or tested.

## Why it was considered

On the Adreno 830 the missed frames of glass-heavy scenes come from render-pass splits at every backdrop read:
freedreno loaded, cleared and stored every bin of the 3392x2400 target around each split (fixed for discarded
depth/stencil clears by Mesa `26.3.1-1+erhai2`, distro branch `eb/mesa-tile-skip`). Vulkan states load/store ops,
transient (lazily allocated) attachments and in-tile MSAA resolve explicitly. Backdrop reads would still split
passes, so any gain has to be measured.

## Known facts

- Turnip on the tablet (`device-logs/eb20-vulkaninfo.txt` in the workspace): Vulkan 1.4, `Adreno (TM) 830v1`,
  a `LAZILY_ALLOCATED` memory type, `VK_EXT_external_memory_dma_buf`, `VK_EXT_image_drm_format_modifier`,
  `VK_EXT_queue_family_foreign`, `VK_KHR_external_semaphore_fd`, `VK_EXT_rasterization_order_attachment_access`.
- Engine build (branch `eb/engine-build`, docs/EB-BUILD.md "Build the Flutter engine"): with
  `shell_enable_vulkan=true` only the embedder's Skia Vulkan surface fails (`embedder_surface_vulkan.{h,cc}`,
  `platform_view_embedder`, `embedder.o`: `ContextType` is absent under slimpeller). Gating it with `!slimpeller`
  like the GL Skia surface is the first step; later link errors are possible.
- deniald hard-codes `FlutterRendererType_kOpenGL` (`compositor/flutter-engine/src/host.rs`) and passes GL-only
  engine flags (`--denial-gl-fbo-zero-is-no-target`, `--denial-float-color`).
- The embedder API has no Vulkan external textures (GL and Metal only); Denial shows every client window as an
  external texture, so dmabuf import into Impeller Vulkan has to be added.

## Work items (unestimated)

1. Engine: Vulkan embedder surface under slimpeller; Impeller-Vulkan external textures from dmabuf (with
   modifiers and sync_file fences); port Denial's GLES-specific engine additions (grep `DENIA_GLES`).
2. deniald: `FlutterVulkanRendererConfig`, Vulkan backing stores exported as scanout dmabufs (UBWC modifier),
   explicit sync to KMS, a runtime switch with GLES as default and fallback.
3. Measure the eb20 animation set against GLES + erhai2 in both presentations; pixel-diff vs eb19.
