// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get settingsApplicationThemingEnabled =>
      'Оформлять поддерживаемые приложения в стиле Denial';

  @override
  String get settingsApplicationThemingDescription =>
      'Применять стиль Denial к поддерживаемым приложениям. Сейчас поддерживается: Kitty.';

  @override
  String get settingsApplicationThemingReapply => 'Применить снова';

  @override
  String get settingsScrollingLayoutSwapTitle => 'Обмен окон местами';

  @override
  String get settingsScrollingLayoutPreserveSwapSizes =>
      'Сохранять размеры окон при обмене';

  @override
  String get settingsScrollingLayoutPreserveSwapSizesDescription =>
      'При обмене местами столбцов из одного окна на том же рабочем пространстве и экране сохранять ширину каждого окна. На вертикальных лентах сохраняется высота. Разделённые столбцы остаются прежнего размера.';

  @override
  String get shellPresentationDesktop => 'Настольный режим';

  @override
  String get shellPresentationMobile => 'Мобильный режим';

  @override
  String get homeResizeWidget => 'Изменить размер виджета';

  @override
  String get homeFolderDefaultName => 'Папка';

  @override
  String get homeFolderGames => 'Игры';

  @override
  String get homeFolderInternet => 'Интернет';

  @override
  String get homeFolderOffice => 'Офис';

  @override
  String get homeFolderGraphics => 'Графика';

  @override
  String get homeFolderMedia => 'Мультимедиа';

  @override
  String get homeFolderDevelopment => 'Разработка';

  @override
  String get homeFolderEducation => 'Образование';

  @override
  String get homeFolderScience => 'Наука';

  @override
  String get homeFolderSystem => 'Система';

  @override
  String get homeFolderUtilities => 'Утилиты';

  @override
  String get homeFolderSettings => 'Настройки';

  @override
  String get homeFolderRename => 'Переименовать папку';

  @override
  String homeFolderApps(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count приложения',
      many: '$count приложений',
      few: '$count приложения',
      one: '$count приложение',
    );
    return '$name, $_temp0';
  }

  @override
  String get actionCancel => 'Отмена';

  @override
  String get actionDismiss => 'Закрыть';

  @override
  String get screenshotSelectionHint => 'Выделите область · Esc — отмена';

  @override
  String get anchorBottomCenter => 'Снизу по центру';

  @override
  String get anchorBottomLeft => 'Снизу слева';

  @override
  String get anchorBottomRight => 'Снизу справа';

  @override
  String get anchorCenter => 'По центру';

  @override
  String get anchorCenterLeft => 'Слева по центру';

  @override
  String get anchorCenterRight => 'Справа по центру';

  @override
  String get anchorTopCenter => 'Сверху по центру';

  @override
  String get anchorTopLeft => 'Сверху слева';

  @override
  String get anchorTopRight => 'Сверху справа';

  @override
  String get batteryCapacityUnavailable => '--';

  @override
  String get batteryCharging => 'Заряжается';

  @override
  String get batteryDischarging => 'Разряжается';

  @override
  String batteryGraphMarker(String label, String value) {
    return '$label $value';
  }

  @override
  String get batteryIdle => 'Не заряжается';

  @override
  String batteryLowNotificationBody(int percent) {
    return 'Заряд батареи: $percent%. Подключите зарядное устройство.';
  }

  @override
  String get batteryLowNotificationTitle => 'Низкий заряд батареи';

  @override
  String get batteryCriticalNotificationTitle => 'Критически низкий заряд';

  @override
  String batteryStateAndPercent(String state, int percent) {
    return '$state $percent%';
  }

  @override
  String get batteryTitle => 'Батарея';

  @override
  String get bluetoothAllow => 'Разрешить';

  @override
  String bluetoothAllowPairing(String deviceName) {
    return 'Разрешить сопряжение с $deviceName?';
  }

  @override
  String get bluetoothAllowService => 'Разрешить службу Bluetooth?';

  @override
  String bluetoothAvailableSignal(int signal) {
    return 'Доступно · $signal дБм';
  }

  @override
  String get bluetoothBlocked => 'Заблокировано';

  @override
  String get bluetoothCloseDetails => 'Закрыть сведения о Bluetooth';

  @override
  String get bluetoothCodeDisplayed => 'Код показан';

  @override
  String bluetoothConfirmCode(String code) {
    return 'Убедитесь, что на обоих устройствах отображается $code.';
  }

  @override
  String bluetoothConfirmDevice(String deviceName) {
    return 'Подтверждение: $deviceName';
  }

  @override
  String bluetoothConnectDeviceStatus(String deviceName, String status) {
    return 'Подключить $deviceName, $status';
  }

  @override
  String get bluetoothConnectedConfiguring => 'Подключено · настройка служб';

  @override
  String bluetoothDevicesConnected(int count) {
    return 'Подключено устройств: $count';
  }

  @override
  String get bluetoothDismissError => 'Закрыть ошибку Bluetooth';

  @override
  String bluetoothEnterPasskey(String deviceName) {
    return 'Введите ключ доступа для $deviceName';
  }

  @override
  String bluetoothEnterPasskeyOnDevice(String deviceName) {
    return 'Введите этот ключ доступа на $deviceName';
  }

  @override
  String bluetoothEnterPin(String deviceName) {
    return 'Введите PIN-код для $deviceName';
  }

  @override
  String bluetoothEnterPinOnDevice(String deviceName) {
    return 'Введите этот PIN-код на $deviceName';
  }

  @override
  String get bluetoothLoadingService => 'Загрузка службы Bluetooth…';

  @override
  String get bluetoothNoAdapter => 'Нет адаптера Bluetooth';

  @override
  String get bluetoothNoAdapterDescription =>
      'Denial включит эти элементы управления, когда появится адаптер.';

  @override
  String get bluetoothNoAdapterShort => 'Нет адаптера';

  @override
  String get bluetoothNoDevices => 'Устройства не найдены';

  @override
  String get bluetoothNoDevicesDescription =>
      'Запустите поиск и включите обнаружение на другом устройстве.';

  @override
  String get bluetoothOff => 'Bluetooth выключен';

  @override
  String get bluetoothOffDescription =>
      'Включите, чтобы увидеть сопряжённые и ближайшие устройства.';

  @override
  String get bluetoothOperationFailed =>
      'Не удалось выполнить запрос Bluetooth.';

  @override
  String bluetoothPairDevice(String deviceName) {
    return 'Выполнить сопряжение с $deviceName';
  }

  @override
  String get bluetoothPairedTrusted => 'Сопряжено · доверенное';

  @override
  String get bluetoothPasskey => 'Ключ доступа Bluetooth';

  @override
  String get bluetoothPasskeyPrivacy =>
      'Ключ доступа один раз передаётся в BlueZ и не сохраняется в Denial.';

  @override
  String bluetoothPasskeyProgress(String code, int enteredDigits) {
    return '$code · введено цифр: $enteredDigits из 6.';
  }

  @override
  String get bluetoothPasskeyRequirements =>
      'Введите числовой ключ доступа длиной до 6 цифр.';

  @override
  String get bluetoothPinCode => 'PIN-код Bluetooth';

  @override
  String get bluetoothPinPrivacy =>
      'PIN-код один раз передаётся в BlueZ и не сохраняется в Denial.';

  @override
  String get bluetoothPinRequirements =>
      'Введите PIN-код длиной от 1 до 16 символов.';

  @override
  String get bluetoothRecognizeDevice =>
      'Продолжайте, только если узнаёте это устройство.';

  @override
  String get bluetoothReject => 'Отклонить';

  @override
  String bluetoothRemoveDevice(String deviceName) {
    return 'Удалить $deviceName';
  }

  @override
  String get bluetoothSameCode => 'один и тот же код';

  @override
  String get bluetoothScanningDescription =>
      'Ближайшие устройства появятся автоматически.';

  @override
  String get bluetoothServiceUnavailable => 'BlueZ недоступен';

  @override
  String get bluetoothServiceUnavailableDescription =>
      'Управление Bluetooth вернётся, когда служба запустится.';

  @override
  String get bluetoothServiceUnavailableShort => 'Bluetooth недоступен';

  @override
  String get bluetoothStopScanning => 'Остановить поиск устройств Bluetooth';

  @override
  String bluetoothStopTrustingDevice(String deviceName) {
    return 'Перестать доверять $deviceName';
  }

  @override
  String get bluetoothSubmit => 'Отправить';

  @override
  String bluetoothTrustDevice(String deviceName) {
    return 'Доверять $deviceName';
  }

  @override
  String bluetoothTrustServiceDevice(String deviceName) {
    return 'Продолжайте, только если доверяете $deviceName.';
  }

  @override
  String bluetoothWaitingForDevice(String code) {
    return '$code · ожидание другого устройства.';
  }

  @override
  String get brightnessTitle => 'Яркость';

  @override
  String get celsiusUnit => '°C';

  @override
  String get chargeProtocolFast => 'БЫСТРАЯ';

  @override
  String get chargeProtocolPowerDelivery => 'PD';

  @override
  String get chargeProtocolPps => 'PPS';

  @override
  String get chargeProtocolVooc => 'VOOC';

  @override
  String get clipboardCloseHistory => 'Закрыть историю буфера обмена';

  @override
  String get clipboardClearAll => 'Очистить всё';

  @override
  String get clipboardDelete => 'Удалить';

  @override
  String get clipboardDeleteItem => 'Удалить элемент буфера обмена';

  @override
  String get clipboardDragToClose =>
      'Перетащите панель буфера обмена к её краю, чтобы закрыть';

  @override
  String get clipboardEmptyDescription =>
      'Скопируйте текст, изображение или файлы — они появятся здесь.';

  @override
  String get clipboardEmptyTitle => 'Пока ничего нет';

  @override
  String get clipboardFileSelection => 'Выбранные файлы';

  @override
  String get clipboardHistoryLockedDescription =>
      'Содержимое буфера обмена скрыто, пока сеанс заблокирован.';

  @override
  String get clipboardHistoryLockedTitle => 'История скрыта';

  @override
  String get clipboardImageFileThumbnail => 'Миниатюра файла изображения';

  @override
  String get clipboardImagePreview =>
      'Предпросмотр изображения из буфера обмена';

  @override
  String get clipboardItemHint =>
      'Нажмите, чтобы вставить в активное приложение. Перетащите, чтобы перенести.';

  @override
  String clipboardItemSemantics(String type, String preview) {
    return 'Элемент буфера обмена: $type. $preview';
  }

  @override
  String get clipboardPin => 'Закрепить';

  @override
  String get clipboardPinItem => 'Закрепить элемент буфера обмена';

  @override
  String get clipboardNoSearchResultsDescription =>
      'Попробуйте другое слово, тип файла или приложение.';

  @override
  String get clipboardNoSearchResultsTitle => 'Ничего не найдено';

  @override
  String get clipboardPreviewUnavailable => 'Предпросмотр недоступен';

  @override
  String get clipboardTypeFiles => 'ФАЙЛЫ';

  @override
  String get clipboardTypeImage => 'ИЗОБРАЖЕНИЕ';

  @override
  String get clipboardTypeText => 'ТЕКСТ';

  @override
  String get clipboardUnpin => 'Открепить';

  @override
  String get clipboardUnpinItem => 'Открепить элемент буфера обмена';

  @override
  String get clipboardUnavailableDescription =>
      'Системная служба истории не ответила.';

  @override
  String get clipboardUnavailableTitle => 'Буфер обмена недоступен';

  @override
  String get commonBluetooth => 'Bluetooth';

  @override
  String get commonCancel => 'Отмена';

  @override
  String get commonChecking => 'Проверка…';

  @override
  String get commonConnecting => 'Подключение…';

  @override
  String get commonError => 'Ошибка';

  @override
  String get commonLimited => 'Ограничено';

  @override
  String get commonLoading => 'Загрузка…';

  @override
  String get commonNotConnected => 'Не подключено';

  @override
  String get commonOff => 'Выкл.';

  @override
  String get commonOn => 'Вкл.';

  @override
  String get commonOnline => 'В сети';

  @override
  String get commonOpening => 'Открытие…';

  @override
  String get commonRetry => 'Повторить';

  @override
  String get commonScanning => 'Поиск…';

  @override
  String commonTitleAndBody(String title, String body) {
    return '$title. $body';
  }

  @override
  String commonTitleAndSubtitle(String title, String subtitle) {
    return '$title, $subtitle';
  }

  @override
  String get commonUnavailable => 'Недоступно';

  @override
  String get commonVolume => 'Громкость';

  @override
  String get commonWifi => 'Wi-Fi';

  @override
  String currentMilliamps(int value) {
    return '$value мА';
  }

  @override
  String get currentMilliampsUnavailable => '-- мА';

  @override
  String desktopActivateWindow(String windowTitle) {
    return 'Перейти к окну $windowTitle';
  }

  @override
  String get desktopAudioOutputDevicesDescription =>
      'Выберите, куда выводить звук.';

  @override
  String get desktopAudioOutputDevicesTitle => 'Устройства вывода';

  @override
  String get desktopAudioOutputDevicesUnavailable =>
      'Устройства вывода звука недоступны.';

  @override
  String get desktopAudioOutputDeviceNotConnected => 'Не подключено';

  @override
  String get desktopApplicationAudioUnavailable =>
      'Звук приложений недоступен.';

  @override
  String desktopApplicationSearchResults(int visible, int total) {
    return 'Приложений: $visible из $total';
  }

  @override
  String get desktopApplicationSuggestionsTitle => 'Рекомендуемые';

  @override
  String get desktopApplicationVolumeDescription =>
      'Настройте громкость отдельных приложений.';

  @override
  String get settingsNavigationYou => 'Вы';

  @override
  String get settingsYouDescription => 'Сделайте это пространство своим.';

  @override
  String get settingsYouPreview => 'Ваш профиль на панели управления';

  @override
  String get settingsYouChoosePhoto => 'Выбрать фото';

  @override
  String get settingsYouDefaultPhoto => 'Аватар по умолчанию';

  @override
  String get settingsYouDisplayName => 'Отображаемое имя';

  @override
  String get settingsYouNameHint =>
      'Оставьте пустым, чтобы использовать имя учётной записи.';

  @override
  String get settingsYouAccountName => 'Использовать имя учётной записи';

  @override
  String get settingsYouSave => 'Сохранить имя';

  @override
  String get settingsYouSaved => 'Имя сохранено.';

  @override
  String get settingsYouImageError =>
      'Не удалось использовать это фото. Выберите изображение PNG, JPEG, WebP, GIF или BMP размером до 16 МБ.';

  @override
  String get settingsYouSaveError =>
      'Не удалось сохранить профиль. Повторите попытку.';

  @override
  String get settingsYouLoadError => 'Не удалось загрузить профиль.';

  @override
  String get desktopCurrentUser => 'Пользователь';

  @override
  String get desktopMixerTitle => 'Микшер';

  @override
  String get desktopApplicationVolumeTitle => 'Громкость приложений';

  @override
  String get desktopApplicationsTitle => 'Приложения';

  @override
  String get desktopChooseWallpaper => 'Выбрать обои';

  @override
  String get desktopClearApplicationSearch => 'Очистить поиск приложений';

  @override
  String get desktopCloseApplicationAudio => 'Закрыть громкость приложений';

  @override
  String get desktopCloseAudioOutputDevices => 'Закрыть устройства вывода';

  @override
  String desktopConnectDevice(String deviceName) {
    return 'Подключить $deviceName';
  }

  @override
  String get desktopDashboardTitle => 'Панель управления';

  @override
  String desktopDisconnectDevice(String deviceName) {
    return 'Отключить $deviceName';
  }

  @override
  String get desktopLoadingAudioOutputDevices => 'Загрузка устройств вывода…';

  @override
  String get desktopEnableBluetoothForDevices =>
      'Включите Bluetooth, чтобы увидеть устройства.';

  @override
  String desktopFeatureAvailability(String feature, String availability) {
    return '$feature: $availability';
  }

  @override
  String get desktopGpuLabel => 'ГП';

  @override
  String get desktopGpuPresetAutomatic => 'Авто';

  @override
  String get desktopGpuPresetHigh => 'Высокий';

  @override
  String get desktopGpuPresetLow => 'Низкий';

  @override
  String desktopInstalledApplications(int count) {
    return 'Установлено приложений: $count';
  }

  @override
  String desktopLaunchApplication(String applicationName) {
    return 'Запустить $applicationName';
  }

  @override
  String get desktopLoadingApplications => 'Загрузка приложений…';

  @override
  String get desktopNoApplicationAudio =>
      'Ни одно приложение не воспроизводит звук.';

  @override
  String get desktopNoAudioOutputDevices =>
      'Устройства вывода звука не найдены.';

  @override
  String get desktopNoApplicationsFound => 'Приложения не найдены';

  @override
  String get desktopOpenApplicationAudio => 'Открыть громкость приложений';

  @override
  String get desktopOpenNotificationCenter => 'Открыть центр уведомлений';

  @override
  String desktopOpenNotificationCenterUnread(int count) {
    return 'Открыть центр уведомлений · непрочитанных: $count';
  }

  @override
  String get desktopOpenPowerControls => 'Открыть управление питанием';

  @override
  String get desktopPboBalanced => 'Сбалансированный';

  @override
  String get desktopPboLabel => 'PBO';

  @override
  String get desktopPboPerformance => 'Производительность';

  @override
  String get desktopPboSilent => 'Тихий';

  @override
  String get desktopPowerModesTitle => 'Режимы питания';

  @override
  String get desktopPowerModesUnavailable => 'Режимы питания недоступны.';

  @override
  String get desktopRefreshApplicationAudio => 'Обновить звук приложений';

  @override
  String get desktopRefreshAudioOutputDevices => 'Обновить устройства вывода';

  @override
  String get desktopRefreshBluetooth => 'Обновить устройства Bluetooth';

  @override
  String get desktopRefreshPowerModes => 'Обновить режимы питания';

  @override
  String desktopRestoreWindow(String windowTitle) {
    return 'Восстановить $windowTitle';
  }

  @override
  String get desktopScanBluetooth => 'Искать устройства Bluetooth';

  @override
  String get desktopSelectAudioOutputDevice =>
      'Выбрать устройство вывода звука';

  @override
  String get desktopScanningBluetoothDevices => 'Поиск устройств Bluetooth…';

  @override
  String get desktopSearchApplications => 'Поиск приложений';

  @override
  String get desktopSystemProfile => 'Профиль системы';

  @override
  String get desktopSystemProfileBalanced => 'Сбалансированный';

  @override
  String get desktopSystemProfilePerformance => 'Производительность';

  @override
  String get desktopSystemProfilePowerSaver => 'Энергосбережение';

  @override
  String get desktopTurnBluetoothOff => 'Выключить Bluetooth';

  @override
  String get desktopTurnBluetoothOn => 'Включить Bluetooth';

  @override
  String desktopVolumeForApplication(String applicationName) {
    return 'Громкость: $applicationName';
  }

  @override
  String frameMilliseconds(String value) {
    return '~$value мс';
  }

  @override
  String get frameMillisecondsUnavailable => '--.- мс';

  @override
  String frameShellPhases(String build, String raster, String gap) {
    return 'UI $build  R $raster  GAP $gap';
  }

  @override
  String frameShellRendering(int refreshRate) {
    return 'SHELL · $refreshRate ГЦ · РЕНДЕР';
  }

  @override
  String frameShellStats(String average, String maximum, int overBudget) {
    return 'СРЕД $average  МАКС $maximum  СВЕРХ $overBudget';
  }

  @override
  String get frameShellWaiting => 'SHELL · ОЖИДАНИЕ';

  @override
  String launchOpeningApplication(String applicationName) {
    return 'Запуск $applicationName';
  }

  @override
  String localApplicationNotRegistered(String appId) {
    return 'Локальное приложение «$appId» не зарегистрировано.';
  }

  @override
  String get lockAuthenticating => 'Проверка…';

  @override
  String get lockAuthenticationResponse => 'Ответ на запрос аутентификации';

  @override
  String get lockAuthenticationUnavailable => 'Аутентификация недоступна.';

  @override
  String get lockCpuLabel => 'ЦП';

  @override
  String get lockDesktopModeEnabled => 'Настольный режим включён';

  @override
  String get lockDesktopPromptDescription =>
      'Введите пароль, чтобы разблокировать этот сеанс.';

  @override
  String get lockHideOnScreenKeyboard => 'Скрыть экранную клавиатуру';

  @override
  String get lockKeyboardBackspace => 'Backspace';

  @override
  String get lockKeyboardLetters => 'Буквы';

  @override
  String get lockKeyboardShift => 'Shift';

  @override
  String get lockKeyboardSpace => 'Пробел';

  @override
  String get lockKeyboardSymbols => 'Символы';

  @override
  String get lockMetricUnavailable => '--';

  @override
  String get lockOnScreenKeyboard => 'Экранная клавиатура';

  @override
  String get lockPamVerified => 'Личность подтверждена';

  @override
  String get lockPasswordObscured => 'Пароль, скрыт';

  @override
  String lockPerformanceMetric(String label, String value) {
    return '$label: $value';
  }

  @override
  String get lockPerformanceStatusLabel => 'Состояние производительности';

  @override
  String get lockPleaseWait => 'Подождите…';

  @override
  String get lockPressEnter => 'Нажмите Enter для разблокировки';

  @override
  String lockRetryInSeconds(int seconds) {
    return 'Повторите через $seconds с';
  }

  @override
  String get lockScreenSemanticsLabel => 'Экран блокировки';

  @override
  String get lockShowOnScreenKeyboard => 'Показать экранную клавиатуру';

  @override
  String get lockSignInSemantics => 'Вход в Denial';

  @override
  String lockTemperature(int temperature) {
    return '$temperature°C';
  }

  @override
  String get lockTryAgain => 'Повторить попытку';

  @override
  String get lockUnlock => 'Разблокировать';

  @override
  String get lockUnlockDenial => 'Разблокировать Denial';

  @override
  String get lockWaitingForAuthentication => 'Ожидание аутентификации…';

  @override
  String get lockWelcomeBack => 'С возвращением';

  @override
  String longDate(String weekday, int day, String month) {
    return '$weekday, $day $month';
  }

  @override
  String get mediaControls => 'Управление воспроизведением';

  @override
  String get mediaNext => 'Следующий трек';

  @override
  String get mediaNowPlaying => 'Сейчас играет';

  @override
  String get mediaPause => 'Пауза';

  @override
  String get mediaPlay => 'Воспроизвести';

  @override
  String get mediaPrevious => 'Предыдущий трек';

  @override
  String get metricAverage => 'СРЕД';

  @override
  String get metricCpu => 'ЦП';

  @override
  String get metricMaximum => 'МАКС';

  @override
  String get metricMinimum => 'МИН';

  @override
  String get metricNow => 'СЕЙЧАС';

  @override
  String get monthApril => 'апреля';

  @override
  String get monthAugust => 'августа';

  @override
  String get monthDecember => 'декабря';

  @override
  String get monthFebruary => 'февраля';

  @override
  String get monthJanuary => 'января';

  @override
  String get monthJuly => 'июля';

  @override
  String get monthJune => 'июня';

  @override
  String get monthMarch => 'марта';

  @override
  String get monthMay => 'мая';

  @override
  String get monthNovember => 'ноября';

  @override
  String get monthOctober => 'октября';

  @override
  String get monthSeptember => 'сентября';

  @override
  String get notificationDismiss => 'Закрыть уведомление';

  @override
  String get notificationGeneric => 'Уведомление';

  @override
  String notificationGroupCollapse(String applicationName) {
    return 'Свернуть уведомления от $applicationName';
  }

  @override
  String notificationGroupExpand(int count, String applicationName) {
    return 'Показать уведомления от $applicationName: $count';
  }

  @override
  String notificationGroupHeader(String applicationName, int count) {
    return '$applicationName · $count';
  }

  @override
  String notificationMessage(String sender, String text) {
    return '$sender: $text';
  }

  @override
  String get notificationNew => 'Новое уведомление';

  @override
  String notificationOpen(String summary) {
    return 'Открыть: $summary';
  }

  @override
  String notificationProgress(int percent) {
    return 'Выполнено: $percent%';
  }

  @override
  String notificationSemantics(String applicationName, String summary) {
    return '$applicationName: $summary';
  }

  @override
  String notificationSemanticsWithBody(
    String applicationName,
    String summary,
    String body,
  ) {
    return '$applicationName: $summary. $body';
  }

  @override
  String get notificationsAllQuiet => 'Всё тихо';

  @override
  String get notificationsClearAll => 'Очистить все уведомления';

  @override
  String get notificationsCloseCenter => 'Закрыть центр уведомлений';

  @override
  String get notificationsDisableDoNotDisturb =>
      'Выключить режим «Не беспокоить»';

  @override
  String get notificationsDoNotDisturbSemantics =>
      'Режим «Не беспокоить» включён. Обычные баннеры не показываются. Критические уведомления по-прежнему могут появляться.';

  @override
  String get notificationsEmptyDescription =>
      'Новые уведомления появятся здесь.';

  @override
  String get notificationsEnableDoNotDisturb =>
      'Включить режим «Не беспокоить»';

  @override
  String get notificationsLoadingPolicy =>
      'Загрузка настроек режима «Не беспокоить»';

  @override
  String get notificationsLockPrivacy =>
      'Конфиденциальность уведомлений на экране блокировки';

  @override
  String get notificationsNone => 'Нет уведомлений';

  @override
  String get notificationsOnLockScreen => 'На экране блокировки';

  @override
  String get notificationsPreviewApplicationOnly => 'Только приложение';

  @override
  String get notificationsPreviewFull => 'Полностью';

  @override
  String get notificationsPreviewHidden => 'Скрыто';

  @override
  String notificationsPreviewModeSemantics(String mode) {
    return 'Предпросмотр на экране блокировки: $mode';
  }

  @override
  String get notificationsQuietMode =>
      'Тихий режим · критические оповещения проходят';

  @override
  String get notificationsTitle => 'Уведомления';

  @override
  String notificationsUnread(int count) {
    return 'Непрочитанных уведомлений: $count';
  }

  @override
  String numberValue(int value) {
    return '$value';
  }

  @override
  String get oskAlt => 'Alt';

  @override
  String get oskAltKey => 'ALT';

  @override
  String get oskArrowDown => 'Вниз';

  @override
  String get oskArrowLeft => 'Влево';

  @override
  String get oskArrowRight => 'Вправо';

  @override
  String get oskArrowUp => 'Вверх';

  @override
  String get oskBackspace => 'Backspace';

  @override
  String get oskCapsLock => 'Caps Lock';

  @override
  String get oskControl => 'Ctrl';

  @override
  String get oskControlKey => 'CTRL';

  @override
  String get oskEnter => 'Enter';

  @override
  String get oskEscape => 'Escape';

  @override
  String get oskEscapeKey => 'ESC';

  @override
  String get oskLetters => 'Буквы';

  @override
  String get oskLettersKey => 'ABC';

  @override
  String get oskMoreSymbols => 'Ещё символы';

  @override
  String get oskMoreSymbolsKey => '=<';

  @override
  String get oskNumbersAndSymbols => 'Цифры и символы';

  @override
  String get oskNumbersAndSymbolsKey => '?123';

  @override
  String get oskShift => 'Shift';

  @override
  String get oskShortcutKeys => 'Клавиши быстрого доступа';

  @override
  String get oskSpace => 'Пробел';

  @override
  String get oskTab => 'Tab';

  @override
  String get oskTabKey => 'TAB';

  @override
  String outputBrightnessSemantics(String outputName) {
    return 'Яркость: $outputName';
  }

  @override
  String outputSoftwareDimmingSemantics(String outputName) {
    return 'Программное затемнение: $outputName';
  }

  @override
  String outputSoftwareDimmingUnavailable(String outputName) {
    return 'Программное затемнение: $outputName (недоступно)';
  }

  @override
  String get outputVolumeSemantics => 'Громкость вывода';

  @override
  String get overviewNoWindows => 'Нет окон';

  @override
  String percentCompact(int percent) {
    return '$percent%';
  }

  @override
  String get percentSign => '%';

  @override
  String percentValue(int percent) {
    String _temp0 = intl.Intl.pluralLogic(
      percent,
      locale: localeName,
      other: '$percent процента',
      many: '$percent процентов',
      few: '$percent процента',
      one: '$percent процент',
    );
    return '$_temp0';
  }

  @override
  String get powerActionHibernate => 'Гибернация';

  @override
  String get powerActionHibernateDescription => 'Сохранить сеанс на диск';

  @override
  String get powerActionLock => 'Заблокировать';

  @override
  String get powerActionLockDescription => 'Немедленно защитить сеанс';

  @override
  String get powerActionLogOut => 'Выйти';

  @override
  String get powerActionLogOutDescription => 'Завершить сеанс Denial';

  @override
  String get powerActionPowerOff => 'Выключить';

  @override
  String get powerActionPowerOffDescription => 'Выключить устройство';

  @override
  String get powerActionRestart => 'Перезагрузить';

  @override
  String get powerActionRestartDescription => 'Перезагрузить устройство';

  @override
  String get powerActionSuspend => 'Спящий режим';

  @override
  String get powerActionSuspendDescription => 'Сохранить сеанс в памяти';

  @override
  String powerAuthenticationRequired(String description) {
    return 'Требуется аутентификация · $description';
  }

  @override
  String powerBlockedBy(String blocker) {
    return 'Приложение препятствует этому действию: $blocker';
  }

  @override
  String get powerConfirmLogOutBody =>
      'Графический сеанс будет завершён. Сохраните работу в открытых приложениях, прежде чем продолжить.';

  @override
  String get powerConfirmLogOutTitle => 'Выйти из Denial?';

  @override
  String get powerConfirmPowerOffBody =>
      'Все приложения будут закрыты, а устройство выключится.';

  @override
  String get powerConfirmPowerOffTitle => 'Выключить устройство?';

  @override
  String get powerConfirmRestartBody =>
      'Все приложения будут закрыты, а система перезагрузится.';

  @override
  String get powerConfirmRestartTitle => 'Перезагрузить устройство?';

  @override
  String powerDelayNotice(String details) {
    return 'Приложение может ненадолго задержать переход в сон или выключение: $details';
  }

  @override
  String get powerPermissionDenied => 'Нет прав в этом сеансе';

  @override
  String get powerPermissionUnavailable => 'Служба сеанса недоступна';

  @override
  String get powerPermissionUnsupported => 'Не поддерживается системой';

  @override
  String get powerSessionBusy => 'Выполняется системный запрос…';

  @override
  String get powerSessionClose => 'Закрыть управление питанием и сеансом';

  @override
  String get powerSessionDescription => 'Выберите, что сделать';

  @override
  String get powerSessionLoading => 'Чтение возможностей системы и блокировок…';

  @override
  String get powerSessionRefresh => 'Обновить возможности питания';

  @override
  String get powerSessionRequestError => 'Системе не удалось выполнить запрос.';

  @override
  String get powerSessionSemantics => 'Управление питанием и сеансом';

  @override
  String get powerSessionTitle => 'Питание и сеанс';

  @override
  String get powerSessionUnavailable =>
      'Системное управление питанием недоступно. Блокировка и выход выполняются самим Denial.';

  @override
  String powerWatts(int watts) {
    return '$watts Вт';
  }

  @override
  String powerWattsDecimal(String watts) {
    return '$watts Вт';
  }

  @override
  String get quickSettingsAutoRotate => 'Автоповорот';

  @override
  String get quickSettingsStayAwake => 'Не засыпать';

  @override
  String get quickSettingsStayAwakeOn => 'Режим «Не засыпать» включён';

  @override
  String get quickSettingsBypassCharging => 'Обходная зарядка';

  @override
  String get quickSettingsScreenRecording => 'Запись экрана';

  @override
  String get quickSettingsRecording => 'Идёт запись';

  @override
  String get quickSettingsBalanced => 'Сбалансированный';

  @override
  String get quickSettingsBatterySaver => 'Энергосбережение';

  @override
  String get quickSettingsClose => 'Закрыть быстрые настройки';

  @override
  String get quickSettingsControls => 'Управление';

  @override
  String get quickSettingsHighPerformance => 'Высокая производительность';

  @override
  String get quickSettingsKeyboard => 'Клавиатура';

  @override
  String get quickSettingsNormal => 'Обычный';

  @override
  String quickSettingsNotificationsCount(int count) {
    return 'Уведомления · $count';
  }

  @override
  String get quickSettingsOneAppActive => 'Активно одно приложение';

  @override
  String quickSettingsOpenDetails(String title) {
    return 'Открыть сведения: $title';
  }

  @override
  String get quickSettingsOpenOnScreen => 'Открыть экранную клавиатуру';

  @override
  String get quickSettingsPerformance => 'Производительность';

  @override
  String get quickSettingsSettingsUnavailable => 'Настройки недоступны.';

  @override
  String get quickSettingsSilent => 'Тихий';

  @override
  String get settingsAboutArchitecture =>
      'Flutter здесь — не надстройка поверх другого композитора. Это часть основы самого композитора.';

  @override
  String get settingsAboutBelief =>
      'Происхождение не обязано определять предназначение.';

  @override
  String get settingsAboutCollaboration =>
      'Создано в постоянном сотрудничестве с моделями ИИ, в основном Sol 6.1 и Opus 5.5.';

  @override
  String get settingsAboutCreditLabel => 'ИДЕЯ, РУКОВОДСТВО И ТЕСТИРОВАНИЕ';

  @override
  String get settingsAboutCreditName => 'Doctor Logix';

  @override
  String get settingsAboutDescription =>
      'Denial даёт Flutter другую жизнь. Он сам управляет всей сценой рабочего стола: оболочкой, её анимацией и компоновкой приложений Wayland.';

  @override
  String get settingsAboutLogoSemanticsLabel => 'Логотип Denial';

  @override
  String get settingsAboutPageSemanticsLabel => 'О Denial';

  @override
  String get settingsAboutTagline =>
      'Композитор Wayland, изначально построенный на Flutter.';

  @override
  String get settingsAccentPickerRouteLabel =>
      'Выбор акцентного цвета оболочки';

  @override
  String get settingsAccentPickerWheelLabel => 'Акцентный цвет оболочки';

  @override
  String get settingsAnimateLockScreen => 'Анимировать экран блокировки';

  @override
  String get settingsAnimateLockScreenDescription =>
      'Показывать короткую анимацию появления рабочего стола; ввод для разблокировки при этом доступен сразу.';

  @override
  String get settingsAnimationSpeed => 'Скорость анимации';

  @override
  String settingsAnimationSpeedValue(int percent) {
    return 'Скорость $percent%';
  }

  @override
  String get settingsAnimationsDescription =>
      'Выберите эффекты закрытия и настройте скорость движения элементов оболочки.';

  @override
  String get settingsAnimationsSection => 'Анимации';

  @override
  String get settingsAnimationsTitle =>
      'Движение под стать вашему рабочему столу.';

  @override
  String get settingsAppearanceDescription =>
      'Изменения сразу применяются ко всему рабочему столу.';

  @override
  String get settingsAppearanceSection => 'Оформление';

  @override
  String get settingsAppearanceTitle => 'Сделайте рабочий стол своим.';

  @override
  String get settingsApplicationAudioDescription =>
      'Настройте активные аудиопотоки по отдельности.';

  @override
  String get settingsApplicationAudioTitle => 'Звук приложений';

  @override
  String get settingsApplicationCategoryAppearance => 'Оформление';

  @override
  String get settingsApplicationCategoryPreferences => 'Параметры';

  @override
  String get settingsApplicationCategorySystem => 'Система';

  @override
  String get settingsApplicationSemanticsLabel => 'Настройки Denial';

  @override
  String get settingsApplicationTitle => 'Настройки';

  @override
  String get settingsAudioDescription =>
      'Управляйте общей громкостью и потоками отдельных приложений.';

  @override
  String get settingsAudioSection => 'Звук';

  @override
  String get settingsAudioTitle => 'Звук для всего рабочего стола.';

  @override
  String get settingsAudioUnavailable => 'Звук приложений недоступен.';

  @override
  String get settingsAutomaticDisplayPowerDescription =>
      'Выключать экраны после периода бездействия.';

  @override
  String get settingsAutomaticDisplayPowerTitle => 'Автоотключение экранов';

  @override
  String get settingsAutomaticDisplayPowerToggle =>
      'Выключать экраны автоматически';

  @override
  String get settingsAutomaticDisplayPowerToggleDescription =>
      'Отключать подключённые экраны при бездействии.';

  @override
  String get settingsAutomaticIdleTitle => 'Действия при бездействии';

  @override
  String get settingsPowerButtonTitle => 'Кнопка питания';

  @override
  String get settingsPowerButtonAction => 'Действие';

  @override
  String get settingsPowerButtonDescription =>
      'Выберите, что происходит при нажатии кнопки питания.';

  @override
  String get settingsPowerButtonSuspend => 'Спящий режим';

  @override
  String get settingsPowerButtonHibernate => 'Гибернация';

  @override
  String get settingsPowerButtonHibernateUnavailable =>
      'Гибернация (недоступно)';

  @override
  String get settingsPowerButtonDpms => 'Выключить экраны (DPMS)';

  @override
  String get settingsPowerButtonPowerOff => 'Выключение';

  @override
  String get settingsPowerButtonLongPress => 'Долгое нажатие';

  @override
  String get settingsPowerButtonLongPressDescription =>
      'Выберите, что происходит при удержании кнопки питания. На телефонах всегда открывается меню питания.';

  @override
  String get settingsPowerButtonLongPressNothing => 'Ничего не делать';

  @override
  String get settingsPowerButtonLongPressMenu => 'Показать меню питания';

  @override
  String get settingsAutomaticLockToggle => 'Блокировать автоматически';

  @override
  String get settingsAutomaticLockToggleDescription =>
      'Показывать экран блокировки и требовать аутентификацию после бездействия.';

  @override
  String get settingsAutomaticSuspendToggle => 'Переходить в сон автоматически';

  @override
  String get settingsAutomaticSuspendToggleDescription =>
      'После длительного бездействия сохранять сеанс в памяти и переходить в режим низкого энергопотребления.';

  @override
  String get settingsSuspendMode => 'Режим сна';

  @override
  String get settingsSuspendModeDescription =>
      'Выберите, как Linux сохраняет питание памяти. Действует при каждом переходе в сон, пока работает Denial.';

  @override
  String get settingsSuspendModeS2idle => 'Сон в режиме простоя (s2idle)';

  @override
  String get settingsSuspendModeShallow => 'Режим ожидания (shallow)';

  @override
  String get settingsSuspendModeDeep => 'Сон в оперативной памяти (deep)';

  @override
  String get settingsSuspendModeUnavailable => 'Недоступно';

  @override
  String get settingsAvailable => 'Доступно';

  @override
  String get settingsAvailableNetworksDescription =>
      'Ближайшие и сохранённые сети Wi-Fi.';

  @override
  String get settingsAvailableNetworksTitle => 'Доступные сети';

  @override
  String get settingsBatteryChargeCycles => 'Циклы зарядки';

  @override
  String get settingsBatteryChargeEnd => 'Стоп';

  @override
  String get settingsBatteryChargeLevel => 'Уровень заряда';

  @override
  String get settingsBatteryChargeLimit => 'Ограничение заряда';

  @override
  String get settingsBatteryChargeLimitDescription =>
      'Ограничить максимальный уровень заряда, чтобы уменьшить износ батареи.';

  @override
  String settingsBatteryChargeLimitEndDescription(int percent) {
    return 'Прекращать зарядку на $percent%, чтобы уменьшить износ батареи.';
  }

  @override
  String get settingsBatteryChargeLimitLevelsReadOnly =>
      'Пороговые уровни задаёт система; в UPower они доступны только для чтения.';

  @override
  String get settingsBatteryChargeLimitOptimizedDescription =>
      'Позволить прошивке выбрать щадящий для батареи режим зарядки.';

  @override
  String settingsBatteryChargeLimitStartEndDescription(int start, int end) {
    return 'Возобновлять зарядку ниже $start% и прекращать на $end%, чтобы уменьшить износ батареи.';
  }

  @override
  String get settingsBatteryChargeStart => 'Старт';

  @override
  String get settingsBatteryCritical => 'Критически низкий заряд';

  @override
  String get settingsBatteryDevice => 'Устройство';

  @override
  String settingsBatteryDuration(int hours, int minutes) {
    return '$hours ч $minutes мин';
  }

  @override
  String get settingsBatteryEmpty => 'Разряжена';

  @override
  String get settingsBatteryFirmwareOptimized => 'Оптимизация прошивкой';

  @override
  String get settingsBatteryFullCapacity => 'Полная ёмкость';

  @override
  String settingsBatteryFullCapacityValue(String full, String design) {
    return '$full / $design Вт·ч';
  }

  @override
  String get settingsBatteryFullyCharged => 'Полностью заряжена';

  @override
  String get settingsBatteryHealth => 'Состояние';

  @override
  String get settingsBatteryInformationTitle => 'Сведения о батарее';

  @override
  String get settingsBatteryLeadAcid => 'Свинцово-кислотная';

  @override
  String get settingsBatteryLithiumIon => 'Литий-ионная';

  @override
  String get settingsBatteryLithiumIronPhosphate => 'Литий-железо-фосфатная';

  @override
  String get settingsBatteryLithiumPolymer => 'Литий-полимерная';

  @override
  String get settingsBatteryLoading => 'Чтение сведений о батарее…';

  @override
  String get settingsBatteryLow => 'Низкий заряд батареи';

  @override
  String get settingsBatteryNickelCadmium => 'Никель-кадмиевая';

  @override
  String get settingsBatteryNickelMetalHydride => 'Никель-металлгидридная';

  @override
  String get settingsBatteryNoSystemBattery =>
      'Системная батарея не обнаружена.';

  @override
  String get settingsBatteryOnBatteryPower => 'От батареи';

  @override
  String get settingsBatteryPendingCharge => 'Ожидание зарядки';

  @override
  String get settingsBatteryPendingDischarge => 'Ожидание разрядки';

  @override
  String get settingsBatteryPluggedIn => 'Подключено к сети';

  @override
  String get settingsBatteryPowerRate => 'Мощность';

  @override
  String get settingsBatteryRefreshing => 'Обновление…';

  @override
  String get settingsBatterySerial => 'Серийный номер';

  @override
  String get settingsBatteryServiceUnavailable =>
      'Сведения о батарее из UPower недоступны.';

  @override
  String get settingsBatteryStoredEnergy => 'Запас энергии';

  @override
  String get settingsBatteryTechnology => 'Технология';

  @override
  String get settingsBatteryTemperature => 'Температура';

  @override
  String get settingsBatteryTimeRemaining => 'Осталось времени';

  @override
  String get settingsBatteryTimeToFull => 'До полной зарядки';

  @override
  String get settingsBatteryUnknownDevice => 'Системная батарея';

  @override
  String get settingsBatteryUpdateFailed =>
      'UPower не удалось обновить или изменить настройки батареи.';

  @override
  String get settingsBatteryVoltage => 'Напряжение';

  @override
  String settingsBatteryWattHours(String value) {
    return '$value Вт·ч';
  }

  @override
  String get settingsBackdropBlur => 'Размытие фона';

  @override
  String get settingsBackdropBlurDescription =>
      'Смягчать содержимое за полупрозрачными окнами и панелями. Более высокое качество сильнее нагружает ГП.';

  @override
  String get settingsBackdropBlurEnabled => 'Включить размытие фона';

  @override
  String get settingsBackdropBlurEnabledDescription =>
      'Размывать только там, где сквозь прозрачное содержимое виден рабочий стол.';

  @override
  String get settingsBackdropBlurIntensity => 'Качество размытия';

  @override
  String get settingsBackdropBlurLevelShitty => 'Паршивое';

  @override
  String get settingsBackdropBlurLevelFast => 'Быстрое';

  @override
  String get settingsBackdropBlurLevelGood => 'Хорошее';

  @override
  String get settingsBackdropBlurLevelBest => 'Лучшее';

  @override
  String get settingsBackdropBlurOpacityThreshold =>
      'Минимальная непрозрачность пикселя для размытия';

  @override
  String get settingsGlassAppearance => 'Вид стекла';

  @override
  String get settingsGlassShellOpacity => 'Непрозрачность стекла оболочки';

  @override
  String get settingsGlassWindowOpacity => 'Непрозрачность стекла окон';

  @override
  String get settingsGlassAppPanelOpacity =>
      'Непрозрачность панелей приложений';

  @override
  String get settingsTransparencyTitle => 'Материал прозрачности';

  @override
  String get settingsTypographyTitle => 'Шрифты';

  @override
  String get settingsTransparencyOff => 'Выкл.';

  @override
  String get settingsTransparencyBlur => 'Размытие';

  @override
  String get settingsTransparencyGlass => 'Стекло';

  @override
  String get settingsTransparencyOffDescription =>
      'Оставлять полупрозрачные поверхности чистыми, не обрабатывая рабочий стол за ними.';

  @override
  String get settingsTransparencyBlurDescription =>
      'Использовать быстрое гауссово размытие фона Denial.';

  @override
  String get settingsTransparencyGlassDescription =>
      'Преломлять чёткое изображение рабочего стола через матовую линзу с акцентным оттенком и направленной подсветкой краёв.';

  @override
  String get settingsGlassFrost => 'Матовость';

  @override
  String get settingsGlassQuality => 'Качество отрисовки';

  @override
  String get settingsGlassThickness => 'Оптическая толщина';

  @override
  String get settingsGlassRefraction => 'Преломление';

  @override
  String get settingsGlassDispersion => 'Цветовая дисперсия';

  @override
  String get settingsGlassSaturation => 'Насыщенность';

  @override
  String get settingsGlassAccentTint => 'Акцентный оттенок';

  @override
  String get settingsGlassBrightness => 'Светимость';

  @override
  String get settingsGlassLightAngle => 'Направление света';

  @override
  String get settingsGlassLightIntensity => 'Интенсивность света';

  @override
  String get settingsGlassEdgeStrength => 'Блеск краёв';

  @override
  String get settingsBackdropDimming => 'Затемнение фона';

  @override
  String get settingsBarGeometryDescription =>
      'Настройте место, отведённое под системную панель рабочего стола.';

  @override
  String get settingsBarGeometryTitle => 'Геометрия системной панели';

  @override
  String get settingsBarThickness => 'Толщина панели';

  @override
  String get settingsBluetoothAdapterDescription => 'Текущий адаптер';

  @override
  String get settingsBluetoothDescription =>
      'Управляйте радиомодулем и подключайте сопряжённые и ближайшие устройства.';

  @override
  String get settingsBluetoothDevicesDescription =>
      'Сопряжённые и ближайшие устройства Bluetooth.';

  @override
  String get settingsBluetoothDevicesTitle => 'Устройства';

  @override
  String get settingsBluetoothEnabled => 'Bluetooth включён';

  @override
  String get settingsBluetoothEnabledDescription =>
      'Разрешить Denial находить и подключать устройства Bluetooth.';

  @override
  String get settingsBluetoothRadioTitle => 'Радиомодуль Bluetooth';

  @override
  String get settingsBluetoothSection => 'Bluetooth';

  @override
  String get settingsBluetoothTitle => 'Устройства Bluetooth.';

  @override
  String get settingsBluetoothUnavailable => 'Управление Bluetooth недоступно.';

  @override
  String get settingsBrightness => 'Яркость';

  @override
  String get settingsCardOpacity => 'Непрозрачность карточек';

  @override
  String get settingsClockScale => 'Масштаб часов';

  @override
  String get settingsCloseEffectExplosion => 'Взрыв';

  @override
  String get settingsCloseEffectFade => 'Затухание';

  @override
  String get settingsCloseEffectImplode => 'Схлопывание';

  @override
  String get settingsCloseEffectNone => 'Нет';

  @override
  String get settingsColorPickerCloseSemanticsLabel => 'Закрыть выбор цвета';

  @override
  String get settingsColorPickerDone => 'Готово';

  @override
  String get settingsColorPickerInstructions =>
      'Выберите цвет на круге или введите точные значения.';

  @override
  String get settingsColorInputTitle => 'Значения цвета';

  @override
  String get settingsColorInputRgb => 'RGB';

  @override
  String get settingsColorInputHsl => 'HSL';

  @override
  String get settingsColorInputHex => 'HEX';

  @override
  String get settingsColorInputRed => 'Красный';

  @override
  String get settingsColorInputGreen => 'Зелёный';

  @override
  String get settingsColorInputBlue => 'Синий';

  @override
  String get settingsColorInputHue => 'Тон';

  @override
  String get settingsColorInputSaturation => 'Насыщенность';

  @override
  String get settingsColorInputLightness => 'Светлота';

  @override
  String get settingsColorInputHexValue => 'HEX-код цвета';

  @override
  String get settingsColorInputNudgeHint =>
      '↑↓ — изменить на 1 · с Shift — на 10';

  @override
  String get settingsColorInputRgbError => 'Значения RGB — от 0 до 255.';

  @override
  String get settingsColorInputHslError =>
      'H — от 0 до 360, S и L — от 0 до 100.';

  @override
  String get settingsColorInputHexError =>
      'Введите 3 или 6 шестнадцатеричных цифр.';

  @override
  String get settingsColorPickerReset => 'Сбросить';

  @override
  String get settingsColorPickerRouteLabel => 'Выбор акцентного цвета оболочки';

  @override
  String get settingsColorPickerTitle => 'Акцентный цвет';

  @override
  String get settingsColorWheelNextHue => 'Следующий тон';

  @override
  String get settingsColorWheelPreviousHue => 'Предыдущий тон';

  @override
  String get settingsColorWheelSemanticsLabel => 'Акцентный цвет оболочки';

  @override
  String get settingsConnect => 'Подключить';

  @override
  String get settingsConnected => 'Подключено';

  @override
  String get settingsConnectedDisplaysDescription =>
      'Разрешение, частота обновления и масштаб для каждого выхода.';

  @override
  String get settingsConnectedDisplaysTitle => 'Подключённые экраны';

  @override
  String get settingsCursorSize => 'Размер курсора';

  @override
  String get settingsCursorTitle => 'Курсор';

  @override
  String get settingsCursorTheme => 'Тема курсора';

  @override
  String get settingsCursorImport => 'Импортировать ZIP с курсорами';

  @override
  String get settingsCursorImporting => 'Импорт…';

  @override
  String get settingsCursorImportFailed =>
      'Не удалось импортировать тему курсора.';

  @override
  String get settingsCursorRemove => 'Удалить импортированную тему курсора';

  @override
  String get settingsCursorRemoveFailed =>
      'Не удалось удалить импортированную тему курсора.';

  @override
  String get settingsCursorAllowApplications =>
      'Разрешить приложениям показывать свой курсор';

  @override
  String get settingsCursorAllowApplicationsDescription =>
      'Приложения Wayland и X11 могут задавать свой вид курсора. Выключите, чтобы всегда использовать выбранную тему Denial.';

  @override
  String get settingsDashboardOverlayDescription =>
      'Расположение панели управления.';

  @override
  String get settingsDashboardOverlayTitle => 'Панель управления';

  @override
  String get settingsDisconnect => 'Отключить';

  @override
  String get settingsApplying => 'Применение…';

  @override
  String get settingsApplyDisplayConfiguration => 'Применить изменения';

  @override
  String get settingsDisplayApplyPersistentHint =>
      'Сохраните изменения, чтобы обновить этот сеанс и файл outputs.conf.';

  @override
  String get settingsDisplayApplySessionHint =>
      'Сохраните изменения, чтобы использовать их в этом сеансе.';

  @override
  String get settingsDisplayConfirmationTitle =>
      'Сохранить эти настройки экрана?';

  @override
  String settingsDisplayConfirmationMessage(int seconds) {
    return 'Прежние настройки экрана будут восстановлены автоматически через $seconds с.';
  }

  @override
  String get settingsDisplayKeepChanges => 'Сохранить изменения';

  @override
  String get settingsDisplayRevertNow => 'Вернуть сейчас';

  @override
  String get settingsDisplayArrangementSemantics =>
      'Редактор расположения мониторов';

  @override
  String get settingsDisplayCanvasPanHint =>
      'Перетаскивайте пустое место, чтобы двигать холст. Колесо мыши меняет масштаб.';

  @override
  String get settingsDisplayCanvasPanSemantics =>
      'Перемещаемый холст мониторов';

  @override
  String get settingsDisplayArrangementTitle => 'Конфигурация мониторов';

  @override
  String get settingsDisplayEnabled => 'Использовать этот экран';

  @override
  String get settingsDisplayEnabledDescription =>
      'Включить этот монитор в рабочий стол. Хотя бы один экран должен оставаться включённым.';

  @override
  String get settingsDisplayBrightnessDescription =>
      'Настройте яркость основного экрана.';

  @override
  String get settingsDisplayBrightnessTitle => 'Яркость';

  @override
  String settingsDisplayDetails(
    int width,
    int height,
    String refreshRate,
    String scale,
  ) {
    return '$width × $height · $refreshRate Гц · $scale×';
  }

  @override
  String get settingsDisplayInformationUnavailable =>
      'Сведения об экране недоступны.';

  @override
  String get settingsDisplaysDescription =>
      'Просмотр подключённых выходов и управление яркостью экрана.';

  @override
  String get settingsDisplaysSection => 'Экраны и видео';

  @override
  String get settingsDisplaysTitle => 'Экраны и видео.';

  @override
  String settingsDisplayPosition(int x, int y) {
    return 'Положение $x, $y';
  }

  @override
  String get settingsDisplayPrimary => 'Основной экран';

  @override
  String get settingsDisplayPrimaryAutomatic =>
      'Автоматически (наибольшая частота обновления)';

  @override
  String get settingsDisplayPrimaryHint =>
      'Элементы оболочки открываются на основном экране. В автоматическом режиме выбирается включённый экран с наибольшей частотой обновления.';

  @override
  String get settingsDisplayRefreshRate => 'Частота обновления';

  @override
  String get settingsDisplayResolution => 'Разрешение';

  @override
  String get settingsDisplayRotation => 'Поворот';

  @override
  String get settingsDisplayRotationNormal => 'Альбомная';

  @override
  String get settingsDisplayRotation90 => '90° против часовой стрелки';

  @override
  String get settingsDisplayRotation180 => 'Перевёрнутая';

  @override
  String get settingsDisplayRotation270 => '90° по часовой стрелке';

  @override
  String get settingsDisplayScrollingLayoutAxis =>
      'Ось прокручиваемой раскладки';

  @override
  String get settingsDisplayScrollingLayoutAxisDescription =>
      'Выберите, как располагаются прокручиваемые окна на этом экране.';

  @override
  String get settingsDisplayScrollingLayoutAxisAuto =>
      'Автоматически (по повороту)';

  @override
  String get settingsDisplayScrollingLayoutAxisHorizontal => 'Горизонтальная';

  @override
  String get settingsDisplayScrollingLayoutAxisVertical => 'Вертикальная';

  @override
  String get settingsDisplayScale => 'Масштаб';

  @override
  String get settingsDisplayScaleInvalid => 'Введите значение от 50 до 600.';

  @override
  String get settingsDisplayScalePreset => 'Готовые значения';

  @override
  String get settingsDisplayScaleRange =>
      'Введите 50–600%. Значение округляется до ближайшего поддерживаемого масштаба. Ниже 100% изображение может быть менее чётким.';

  @override
  String get settingsDisplayVariableRefreshRate =>
      'Переменная частота обновления (VRR)';

  @override
  String get settingsDisplayVariableRefreshRateDescription =>
      'Подстраивать частоту обновления монитора под выводимое содержимое.';

  @override
  String get settingsDisplayZoomFit => 'Показать все мониторы';

  @override
  String get settingsDisplayZoomIn => 'Увеличить';

  @override
  String settingsDisplayZoomLevel(int percent) {
    return 'Масштаб холста $percent%';
  }

  @override
  String get settingsDisplayZoomOut => 'Уменьшить';

  @override
  String get settingsLoadingDisplays => 'Загрузка конфигурации мониторов…';

  @override
  String get settingsMonitorDragHint =>
      'Перетащите, чтобы расположить, или двигайте клавишами со стрелками.';

  @override
  String settingsMonitorSemantics(String name) {
    return 'Монитор $name';
  }

  @override
  String get settingsEdgeDistance => 'Отступ от края';

  @override
  String get settingsFocusedWindows => 'Активные окна';

  @override
  String get settingsFontCatalogLoading => 'Поиск установленных шрифтов…';

  @override
  String get settingsFontDescription =>
      'Использовать в оболочке Denial системный шрифт по умолчанию или любой установленный.';

  @override
  String get settingsFontFamily => 'Шрифт';

  @override
  String get settingsFontSystemDefault => 'Системный по умолчанию';

  @override
  String get settingsFocusedWindowBorder => 'Выделять рамку активного окна';

  @override
  String get settingsFocusedWindowBorderDescription =>
      'Выключите, чтобы рамки активных и неактивных окон были одного цвета.';

  @override
  String get settingsHeaderContext => 'DENIAL / СИСТЕМА';

  @override
  String get settingsHeaderLogoSemanticsLabel => 'Denial';

  @override
  String get settingsHeight => 'Высота';

  @override
  String get settingsHoverTrigger => 'Открывать при наведении на край';

  @override
  String get settingsHoverTriggerDescription =>
      'Показывать эту панель, когда указатель достигает её края экрана.';

  @override
  String get settingsHudOverlayDescription =>
      'Расположение индикатора громкости и яркости.';

  @override
  String get settingsHudOverlayTitle => 'Индикатор уровня';

  @override
  String get settingsDisplayOffTimeout => 'Выключать экраны через';

  @override
  String get settingsIdleInhibitDescription =>
      'Активность приложений, например воспроизведение видео, может временно приостанавливать эти таймеры.';

  @override
  String get settingsIdleInhibitSemantics =>
      'Приложения могут приостанавливать действия при бездействии';

  @override
  String get settingsInactivityTimeout => 'Время бездействия';

  @override
  String get settingsLockTimeout => 'Блокировать через';

  @override
  String get settingsLauncherOverlayDescription =>
      'Расположение меню приложений.';

  @override
  String get settingsLauncherOverlayTitle => 'Приложения';

  @override
  String get settingsLanguageDescription =>
      'Вариант «Как в системе» следует языку системы. Изменения применяются сразу.';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageInterfaceTitle => 'Язык интерфейса';

  @override
  String get settingsLanguageSection => 'Язык';

  @override
  String get settingsLanguageSelectorSemantics => 'Язык интерфейса Denial';

  @override
  String get settingsLanguageSimplifiedChinese => '简体中文';

  @override
  String get settingsLanguageRussian => 'Русский';

  @override
  String get settingsLanguageSystemDefault => 'Как в системе';

  @override
  String get settingsLanguageTitle => 'Выберите язык Denial.';

  @override
  String get settingsKeyboardSection => 'Ввод';

  @override
  String get settingsKeyboardTitle =>
      'Настройте физическую клавиатуру для Flutter, Wayland и Xwayland.';

  @override
  String get settingsKeyboardLayoutsTitle => 'Раскладки и варианты';

  @override
  String get settingsKeyboardLayoutsDescription =>
      'Введите раскладки в порядке переключения. Вариант указывается после двоеточия, например: us, de:nodeadkeys.';

  @override
  String get settingsKeyboardLayoutsLabel => 'Раскладки';

  @override
  String get settingsKeyboardLayoutsHint => 'us, ru';

  @override
  String get settingsKeyboardOptionsLabel => 'Параметры XKB';

  @override
  String get settingsKeyboardOptionsHint => 'compose:menu, caps:escape';

  @override
  String get settingsKeyboardOptionsDescription =>
      'Параметры через запятую включают Compose, альтернативные сочетания для смены раскладки, переназначение Caps и другое поведение XKB.';

  @override
  String get settingsKeyboardRepeatTitle => 'Повтор клавиш';

  @override
  String get settingsKeyboardRepeatDelay => 'Задержка';

  @override
  String get settingsKeyboardRepeatRate => 'Частота';

  @override
  String get settingsKeyboardSwitchingTitle => 'Переключение раскладки';

  @override
  String get settingsKeyboardActiveLayout => 'Текущая раскладка';

  @override
  String get settingsKeyboardSwitchingShortcut =>
      'Super+Пробел выбирает следующую раскладку. С Shift — предыдущую.';

  @override
  String get settingsKeyboardApply => 'Применить настройки клавиатуры';

  @override
  String get settingsKeyboardApplying => 'Применение…';

  @override
  String get settingsKeyboardLoading =>
      'Чтение конфигурации клавиатуры композитора…';

  @override
  String get settingsKeyboardInvalidLayouts =>
      'Введите хотя бы одну допустимую раскладку XKB.';

  @override
  String get settingsTouchpadSection => 'Ввод';

  @override
  String get settingsTouchpadTitle => 'Настройте поведение мыши и тачпада.';

  @override
  String get settingsTouchpadTapToClick => 'Касание для нажатия';

  @override
  String get settingsTouchpadTapToClickDescription =>
      'Касание тачпада нажимает основную кнопку мыши.';

  @override
  String get settingsTouchpadNaturalScroll =>
      'Обратная прокрутка двумя пальцами';

  @override
  String get settingsTouchpadNaturalScrollDescription =>
      'Содержимое движется в том же направлении, что и пальцы.';

  @override
  String get settingsTouchpadScrollSpeed => 'Скорость прокрутки пальцами';

  @override
  String get settingsTouchpadScrollingLayoutSwipeSpeed =>
      'Скорость смахивания в прокручиваемой раскладке';

  @override
  String get settingsMousePointerSpeed => 'Скорость указателя мыши';

  @override
  String get settingsMouseAcceleration => 'Ускорение мыши';

  @override
  String get settingsMouseAccelerationDescription =>
      'Чем быстрее движение, тем дальше уходит указатель. Если выключено, указатель точно следует за рукой.';

  @override
  String get settingsShortcutsSection => 'Сочетания клавиш';

  @override
  String get settingsShortcutsTitle =>
      'Выберите, что делает Denial при нажатии сочетания клавиш.';

  @override
  String settingsShortcutsConfigured(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count сочетания клавиш',
      many: '$count сочетаний клавиш',
      few: '$count сочетания клавиш',
      one: '$count сочетание клавиш',
      zero: 'Нет сочетаний клавиш',
    );
    return '$_temp0';
  }

  @override
  String get settingsShortcutsAdd => 'Добавить сочетание';

  @override
  String get settingsShortcutsLoading =>
      'Чтение сочетаний клавиш из композитора…';

  @override
  String get settingsShortcutsUnavailable =>
      'Конфигурация сочетаний клавиш композитора недоступна.';

  @override
  String get settingsShortcutsRetry => 'Повторить';

  @override
  String get settingsShortcutsEmpty =>
      'Сочетания клавиш не настроены. Добавьте сочетание, чтобы быстрее выполнять нужное действие.';

  @override
  String settingsShortcutsRowSemantics(String shortcut, String action) {
    return '$shortcut, $action';
  }

  @override
  String settingsShortcutsDeleteTooltip(String shortcut) {
    return 'Удалить $shortcut';
  }

  @override
  String get settingsShortcutEditorAddTitle => 'Добавить сочетание';

  @override
  String get settingsShortcutEditorEditTitle => 'Изменить сочетание';

  @override
  String get settingsShortcutEditorDescription =>
      'Введите сочетание, выберите, что оно запускает, — композитор проверит его перед сохранением.';

  @override
  String get settingsShortcutEditorShortcutLabel => 'Сочетание';

  @override
  String get settingsShortcutEditorShortcutHint => 'Super+K';

  @override
  String get settingsShortcutEditorShortcutExample =>
      'Примеры: Super+K · Ctrl+Alt+Backspace · ThreeFingerSwipeLeft';

  @override
  String get settingsShortcutEditorSupportedInputs => 'Поддерживаемый ввод';

  @override
  String get settingsShortcutEditorTargetLabel => 'Запускает';

  @override
  String get settingsShortcutEditorTargetAction => 'Действие Denial';

  @override
  String get settingsShortcutEditorTargetApplication => 'Приложение';

  @override
  String get settingsShortcutEditorTargetProgram => 'Программа';

  @override
  String get settingsShortcutEditorTargetShell => 'Команда оболочки';

  @override
  String get settingsShortcutEditorProgramDescription =>
      'Запустить программу напрямую, без командной оболочки. Каждый аргумент передаётся в точности как написан.';

  @override
  String get settingsShortcutEditorProgramLabel => 'Программа';

  @override
  String get settingsShortcutEditorProgramHint => 'foot';

  @override
  String get settingsShortcutEditorArgumentsLabel => 'Аргументы';

  @override
  String get settingsShortcutEditorAddArgument => 'Добавить аргумент';

  @override
  String get settingsShortcutEditorNoArguments => 'Нет аргументов';

  @override
  String settingsShortcutEditorArgumentLabel(int index) {
    return 'Аргумент $index';
  }

  @override
  String get settingsShortcutEditorArgumentHint => '--option';

  @override
  String settingsShortcutEditorRemoveArgument(int index) {
    return 'Удалить аргумент $index';
  }

  @override
  String get settingsShortcutEditorShellDescription =>
      'Выполнить одну команду через sh -c. Поддерживаются переменные оболочки, конвейеры, перенаправления и цепочки команд.';

  @override
  String get settingsShortcutEditorShellCommandLabel => 'Команда оболочки';

  @override
  String get settingsShortcutEditorShellCommandHint =>
      'grim -g \"\$(slurp)\" ~/Pictures/capture.png';

  @override
  String get settingsShortcutEditorChooseAction => 'Выберите действие';

  @override
  String get settingsShortcutEditorChooseApplication => 'Выберите приложение';

  @override
  String settingsShortcutApplicationTarget(String desktopFileId) {
    return 'Приложение · $desktopFileId';
  }

  @override
  String get settingsShortcutEditorValidating => 'Проверка композитором…';

  @override
  String settingsShortcutEditorValid(String shortcut) {
    return 'Распознано как $shortcut';
  }

  @override
  String settingsShortcutEditorConflict(String shortcut, String action) {
    return '$shortcut уже назначено действию «$action».';
  }

  @override
  String get settingsShortcutEditorSearch => 'Поиск';

  @override
  String get settingsShortcutEditorNoResults => 'Ничего не найдено.';

  @override
  String get settingsShortcutEditorBack => 'Назад к редактору сочетания';

  @override
  String get settingsShortcutEditorDone => 'Готово';

  @override
  String get settingsShortcutEditorCancel => 'Отмена';

  @override
  String get settingsShortcutEditorSave => 'Сохранить';

  @override
  String get settingsShortcutEditorSaving => 'Сохранение…';

  @override
  String get settingsShortcutEditorDelete => 'Удалить';

  @override
  String get settingsShortcutGestureThreeFingerSwipeUp =>
      'Смахивание тремя пальцами вверх';

  @override
  String get settingsShortcutGestureThreeFingerSwipeLeft =>
      'Смахивание тремя пальцами влево';

  @override
  String get settingsShortcutGestureThreeFingerSwipeRight =>
      'Смахивание тремя пальцами вправо';

  @override
  String get settingsShortcutGestureFourFingerSwipeLeft =>
      'Смахивание четырьмя пальцами влево';

  @override
  String get settingsShortcutGestureFourFingerSwipeRight =>
      'Смахивание четырьмя пальцами вправо';

  @override
  String get settingsShortcutGestureFourFingerSwipeUp =>
      'Смахивание четырьмя пальцами вверх';

  @override
  String get settingsShortcutGestureFourFingerSwipeDown =>
      'Смахивание четырьмя пальцами вниз';

  @override
  String get settingsShortcutInputCategoryModifier => 'Модификаторы';

  @override
  String get settingsShortcutInputCategoryNavigation => 'Навигация';

  @override
  String get settingsShortcutInputCategoryEditing => 'Редактирование';

  @override
  String get settingsShortcutInputCategoryPunctuation => 'Пунктуация';

  @override
  String get settingsShortcutInputCategoryFunction => 'Функциональные';

  @override
  String get settingsShortcutInputCategoryMedia => 'Мультимедиа';

  @override
  String get settingsShortcutInputCategoryHardware => 'Аппаратные';

  @override
  String get settingsShortcutInputCategorySpecial => 'Специальные';

  @override
  String get settingsShortcutInputCategoryGesture => 'Жесты';

  @override
  String get settingsShortcutActionShutdown => 'Выключить устройство';

  @override
  String get settingsShortcutActionOpenApplications => 'Открыть приложения';

  @override
  String get settingsShortcutActionOpenDashboard => 'Открыть панель управления';

  @override
  String get settingsShortcutActionOpenSettings => 'Открыть настройки';

  @override
  String get settingsShortcutActionOpenOverview => 'Открыть обзор';

  @override
  String get settingsShortcutActionToggleVerticalMaximize =>
      'Развернуть по вертикали';

  @override
  String get settingsShortcutActionWindowSwitcher => 'Переключить окна';

  @override
  String get settingsShortcutActionOpenClipboard => 'Открыть буфер обмена';

  @override
  String get settingsShortcutActionCaptureRegion => 'Снимок области';

  @override
  String get settingsShortcutActionCloseWindow => 'Закрыть окно';

  @override
  String get settingsShortcutActionMinimizeWindow => 'Свернуть окно';

  @override
  String get settingsShortcutActionMinimizeAllWindows => 'Свернуть все окна';

  @override
  String get settingsShortcutActionToggleMaximize =>
      'Развернуть или восстановить';

  @override
  String get settingsShortcutActionToggleFullscreen =>
      'Полноэкранный режим: вкл./выкл.';

  @override
  String get settingsShortcutActionToggleWindowAlwaysOnTop =>
      'Поверх всех окон: вкл./выкл.';

  @override
  String get settingsShortcutActionReleasePointer => 'Освободить указатель';

  @override
  String get settingsShortcutActionLockScreen => 'Заблокировать экран';

  @override
  String get settingsShortcutActionVolumeUp => 'Увеличить громкость';

  @override
  String get settingsShortcutActionVolumeDown => 'Уменьшить громкость';

  @override
  String get settingsShortcutActionVolumeMute => 'Звук: вкл./выкл.';

  @override
  String get settingsShortcutActionBrightnessUp => 'Увеличить яркость';

  @override
  String get settingsShortcutActionBrightnessDown => 'Уменьшить яркость';

  @override
  String get settingsShortcutActionNextKeyboardLayout =>
      'Следующая раскладка клавиатуры';

  @override
  String get settingsShortcutActionPreviousKeyboardLayout =>
      'Предыдущая раскладка клавиатуры';

  @override
  String get settingsShortcutActionFocusLeft => 'Фокус на окно слева';

  @override
  String get settingsShortcutActionFocusRight => 'Фокус на окно справа';

  @override
  String get settingsShortcutActionFocusUp => 'Фокус на окно сверху';

  @override
  String get settingsShortcutActionFocusDown => 'Фокус на окно снизу';

  @override
  String get settingsShortcutActionSwapLeft => 'Поменять с окном слева';

  @override
  String get settingsShortcutActionSwapRight => 'Поменять с окном справа';

  @override
  String get settingsShortcutActionSwapUp => 'Поменять с окном сверху';

  @override
  String get settingsShortcutActionSwapDown => 'Поменять с окном снизу';

  @override
  String get settingsShortcutActionPreviousWorkspace =>
      'Предыдущее рабочее пространство';

  @override
  String get settingsShortcutActionNextWorkspace =>
      'Следующее рабочее пространство';

  @override
  String get settingsShortcutActionMoveToPreviousWorkspace =>
      'Переместить окно на предыдущее рабочее пространство';

  @override
  String get settingsShortcutActionMoveToNextWorkspace =>
      'Переместить окно на следующее рабочее пространство';

  @override
  String settingsShortcutActionSwitchWorkspace(int workspace) {
    return 'Перейти на рабочее пространство $workspace';
  }

  @override
  String settingsShortcutActionMoveToWorkspace(int workspace) {
    return 'Переместить окно на рабочее пространство $workspace';
  }

  @override
  String get settingsLayoutDescription =>
      'Настройте отступы вокруг обычных и развёрнутых окон.';

  @override
  String get settingsLayoutSection => 'Раскладка рабочего стола';

  @override
  String get settingsLayoutTitle => 'Дайте каждому окну простор.';

  @override
  String get settingsWindowLayoutDescription =>
      'В режиме наложения окна могут перекрываться. Мозаика динамически делит рабочий стол. Прокрутка следует за фокусом вдоль ленты; её ось настраивается для каждого экрана и по умолчанию зависит от поворота.';

  @override
  String get settingsWindowLayoutDwindle => 'Мозаика';

  @override
  String get settingsWindowLayoutStacking => 'Наложение';

  @override
  String get settingsWindowLayoutScrolling => 'Прокрутка';

  @override
  String get settingsWindowLayoutTitle => 'Раскладка окон';

  @override
  String get settingsScrollingLayoutWheelTitle => 'Super + колесо мыши';

  @override
  String get settingsScrollingLayoutWheelDescription =>
      'Удерживайте Super и вращайте колесо мыши, чтобы прокручивать ленту окон.';

  @override
  String get settingsScrollingLayoutWheelSpeed => 'Скорость колеса';

  @override
  String get settingsScrollingLayoutWheelUpDirection =>
      'Колесо вверх прокручивает';

  @override
  String get settingsScrollingLayoutWheelUpLeft => 'Влево';

  @override
  String get settingsScrollingLayoutWheelUpRight => 'Вправо';

  @override
  String get settingsWorkspacesTitle => 'Рабочие пространства';

  @override
  String get settingsWorkspacesEnable => 'Включить рабочие пространства';

  @override
  String get settingsWorkspacesDescription =>
      'Каждый монитор переключает рабочие пространства независимо. Свёрнутые окна доступны на всех рабочих пространствах своего монитора.';

  @override
  String get settingsWorkspaceCount => 'Число рабочих пространств';

  @override
  String get settingsWorkspaceSwitchingOrientation =>
      'Направление переключения';

  @override
  String get settingsWorkspaceSwitchingHorizontal => 'Горизонтальное';

  @override
  String get settingsWorkspaceSwitchingVertical => 'Вертикальное';

  @override
  String workspaceLabel(int workspace) {
    return 'Рабочее пространство $workspace';
  }

  @override
  String get workspaceActive => 'активно';

  @override
  String get workspaceOccupied => 'занято';

  @override
  String get workspaceEmpty => 'пусто';

  @override
  String get settingsLiveBadge => 'СРАЗУ';

  @override
  String get settingsLiveChangesSemanticsLabel => 'Изменения применяются сразу';

  @override
  String get settingsLoadingAudio => 'Загрузка звука приложений…';

  @override
  String get settingsLockBackdropDescription =>
      'Настройте затемнение и размытие обоев на экране блокировки.';

  @override
  String get settingsLockBackdropTitle => 'Фон';

  @override
  String get settingsLockInformationDescription =>
      'Выберите, какие полезные сведения видны до входа.';

  @override
  String get settingsLockInformationTitle => 'Состояние системы';

  @override
  String get settingsLockMotionDescription =>
      'Анимировать появление экрана блокировки.';

  @override
  String get settingsLockMotionTitle => 'Анимация экрана блокировки';

  @override
  String get settingsLockPreviewDate => 'Четверг, 23 июля';

  @override
  String get settingsLockPreviewSemantics => 'Предпросмотр экрана блокировки';

  @override
  String get settingsLockPreviewStatus => 'ЦП 18% · ГП 12% · 52°C';

  @override
  String get settingsLockPreviewTime => '22:41';

  @override
  String get settingsLockScreenDescription =>
      'На основном экране — продуманная сцена входа, на остальных — спокойный информативный вид.';

  @override
  String get settingsLockScreenSection => 'Экран блокировки';

  @override
  String get settingsLockScreenTitle =>
      'Экран блокировки для рабочего стола, а не растянутый телефонный.';

  @override
  String get settingsMasterOutputDescription =>
      'Задайте текущую громкость вывода.';

  @override
  String get settingsMasterOutputTitle => 'Общая громкость';

  @override
  String get settingsMaximizedSpacingDescription =>
      'Оставлять небольшой отступ вокруг развёрнутых окон.';

  @override
  String get settingsMaximizedSpacingTitle => 'Отступ развёрнутых окон';

  @override
  String get settingsDeveloperAutoReloadDescription =>
      'Denial будет следить за рабочим каталогом и перезагружать успешные изменения исходного кода. Доступно, если установлен системный мост инструментов.';

  @override
  String get settingsDeveloperAutoReloadTitle =>
      'Перезагружать при изменении файлов';

  @override
  String get settingsDeveloperBuildOptimized =>
      'Собрать и включить оптимизированную';

  @override
  String get settingsDeveloperBuildRecoveryDescription =>
      'Превратите текущий рабочий каталог в оптимизированную оболочку или вернитесь к заведомо рабочему интерфейсу без перезапуска сеанса Wayland.';

  @override
  String get settingsDeveloperBuildRecoveryTitle => 'Сборка и восстановление';

  @override
  String get settingsDeveloperDescription =>
      'Редактируйте весь рабочий стол на Flutter, перезагружайте его на лету, а затем превратите в оптимизированную сборку.';

  @override
  String get settingsDeveloperDiagnosticsTitle => 'Подключение и диагностика';

  @override
  String get settingsDeveloperEditorAttachDescription =>
      'Откройте рабочий каталог оболочки Flutter в VSCodium, выберите «Attach to Denial live UI» в разделе Run and Debug, затем сохраняйте изменённые файлы Dart — рабочий стол перезагрузится. Изменения системной части композитора требуют обычной пересборки.';

  @override
  String get settingsDeveloperEnableDescription =>
      'Запустить выбранный рабочий каталог с сервисом Dart VM, доступным для VSCodium и инструментов Flutter.';

  @override
  String get settingsDeveloperEnableTitle =>
      'Включить разработку интерфейса на лету';

  @override
  String get settingsDeveloperGeneration => 'Поколение';

  @override
  String get settingsDeveloperHotReload => 'Горячая перезагрузка';

  @override
  String get settingsDeveloperHotRestart => 'Горячий перезапуск';

  @override
  String get settingsDeveloperLiveControlsTitle => 'Сеанс разработки';

  @override
  String get settingsDeveloperModeCustom => 'Своя оптимизированная';

  @override
  String get settingsDeveloperModeLive => 'Разработка на лету';

  @override
  String get settingsDeveloperModeOfficial => 'Официальная оптимизированная';

  @override
  String get settingsDeveloperModeUnavailable => 'Подключение';

  @override
  String get settingsDeveloperNoDiagnostics => 'Диагностических сообщений нет.';

  @override
  String get settingsDeveloperPerformanceWarning =>
      'Разработка на лету использует движок Flutter с JIT и отладочные проверки. Плавность кадров и производительность в играх будут ниже, пока вы не вернётесь к оптимизированной сборке.';

  @override
  String get settingsDeveloperRefreshStatus => 'Обновить состояние';

  @override
  String get settingsDeveloperRestoreOfficial =>
      'Вернуть официальный интерфейс';

  @override
  String get settingsDeveloperRevertLastWorking => 'Вернуть последний рабочий';

  @override
  String get settingsDeveloperRuntimeTitle =>
      'Среда выполнения оболочки Flutter';

  @override
  String get settingsDeveloperSection => 'Для разработчиков';

  @override
  String get settingsDeveloperSetupAction =>
      'Создать и запустить редактируемый интерфейс';

  @override
  String get settingsDeveloperSetupDescription =>
      'Клонировать исходный код Denial соответствующей версии с GitHub в ~/DenialUI, подготовить его закреплённым набором инструментов и перейти к разработке на лету.';

  @override
  String get settingsDeveloperSetupRunning =>
      'Подготовка редактируемого интерфейса. Оболочка переключится автоматически, когда он будет готов…';

  @override
  String get settingsDeveloperSetupUnavailable =>
      'Установите denial-ui-development, чтобы включить автоматическую настройку.';

  @override
  String get settingsDeveloperUseWorkspace => 'Использовать этот каталог';

  @override
  String get settingsDeveloperVmServiceTitle => 'Сервис Dart VM';

  @override
  String get settingsDeveloperWaitingForStatus =>
      'Ожидание состояния среды выполнения…';

  @override
  String get settingsDeveloperWorkspaceDescription =>
      'Выберите проект Flutter с файлами pubspec.yaml и lib/main.dart. Изменениями исходного кода можно заменить любой интерфейс оболочки, не требующий нового системного протокола.';

  @override
  String get settingsDeveloperWorkspaceFieldLabel =>
      'Рабочий каталог исходного кода Flutter';

  @override
  String get settingsDeveloperWorkspaceHint => '/home/you/DenialUI/dart_shell';

  @override
  String get settingsDeveloperWorkspaceNotReady => 'Требуется настройка';

  @override
  String get settingsDeveloperWorkspaceReady => 'Готов';

  @override
  String get settingsDeveloperWorkspaceTitle =>
      'Рабочий каталог исходного кода';

  @override
  String get settingsEnvironmentAdd => 'Добавить';

  @override
  String get settingsEnvironmentAddedStatus =>
      'Добавлено в запускаемые приложения';

  @override
  String get settingsEnvironmentAddModeDescription =>
      'Передавать заданное значение, когда Denial запускает приложение. Пустое значение сохраняется как пустая строка.';

  @override
  String get settingsEnvironmentAllApplications => 'Все приложения';

  @override
  String get settingsEnvironmentAllApplicationsDescription =>
      'Окружение запуска по умолчанию';

  @override
  String settingsEnvironmentApplicationInherited(int count) {
    return 'Наследует общих правил: $count';
  }

  @override
  String get settingsEnvironmentApplicationSearchHint =>
      'Поиск приложений или идентификаторов desktop-файлов';

  @override
  String get settingsEnvironmentApplicationsTitle => 'Приложения';

  @override
  String get settingsEnvironmentApplicationsUnavailable =>
      'Не удалось загрузить установленные приложения.';

  @override
  String get settingsEnvironmentBackToApplications => 'Назад к приложениям';

  @override
  String get settingsEnvironmentCancel => 'Отмена';

  @override
  String get settingsEnvironmentClearScope => 'Очистить';

  @override
  String settingsEnvironmentDeleteVariable(String variable) {
    return 'Удалить $variable';
  }

  @override
  String settingsEnvironmentEditVariable(String variable) {
    return 'Изменить $variable';
  }

  @override
  String get settingsEnvironmentEditorDescription =>
      'Задайте значение, оставьте его пустым, чтобы передать пустую строку, или выберите «Удалить», чтобы переменная не попала в дочерний процесс.';

  @override
  String settingsEnvironmentEditorEditTitle(String variable) {
    return 'Изменение $variable';
  }

  @override
  String get settingsEnvironmentEditorTitle => 'Добавить переопределение';

  @override
  String get settingsEnvironmentEmptyDescription =>
      'Добавьте переменную выше, чтобы изменить окружение приложений, запускаемых в дальнейшем.';

  @override
  String get settingsEnvironmentEmptyTitle => 'Нет переопределений';

  @override
  String get settingsEnvironmentEmptyValue => 'Пустая строка';

  @override
  String get settingsEnvironmentHiddenStatus =>
      'Скрыто от запускаемых приложений';

  @override
  String get settingsEnvironmentHide => 'Скрыть';

  @override
  String get settingsEnvironmentHideModeDescription =>
      'Убирать унаследованную переменную непосредственно перед exec. Приложение ведёт себя так, будто она никогда не экспортировалась.';

  @override
  String get settingsEnvironmentNameDuplicate =>
      'Для этой переменной уже есть переопределение.';

  @override
  String get settingsEnvironmentNameHint => 'например, MOZ_ENABLE_WAYLAND';

  @override
  String get settingsEnvironmentNameInvalid =>
      'Используйте латинские буквы, цифры и подчёркивания; первым должна быть буква или подчёркивание.';

  @override
  String get settingsEnvironmentNameLabel => 'Имя переменной';

  @override
  String get settingsEnvironmentNameRequired => 'Введите имя переменной.';

  @override
  String get settingsEnvironmentOverridesDefault =>
      'Переопределяет общее правило для всех приложений';

  @override
  String get settingsEnvironmentModeAdd => 'Добавить переменную';

  @override
  String get settingsEnvironmentModeHide => 'Скрыть переменную';

  @override
  String get settingsEnvironmentRemoveDescription =>
      'Denial удалит эту унаследованную переменную перед запуском приложения.';

  @override
  String get settingsEnvironmentRemoveLabel =>
      'Удалять из запускаемых приложений';

  @override
  String get settingsEnvironmentRemovedValue =>
      'Удалена из дочернего окружения';

  @override
  String get settingsEnvironmentScopeDescription =>
      'Эти переопределения действуют только на приложения и команды сочетаний клавиш, которые запускает Denial. Они влияют на последующие запуски, но не на записи автозапуска XDG, службы systemd, службы D-Bus и сам Denial.';

  @override
  String get settingsEnvironmentScopeTitle => 'Область действия';

  @override
  String get settingsEnvironmentSection => 'Приложения';

  @override
  String get settingsEnvironmentTitle =>
      'Настройте окружение приложений, которые запускает Denial.';

  @override
  String get settingsEnvironmentUpdate => 'Обновить переменную';

  @override
  String get settingsEnvironmentUnavailableApplication =>
      'Недоступное приложение';

  @override
  String get settingsEnvironmentValueHint => 'например, 1';

  @override
  String get settingsEnvironmentValueLabel => 'Значение';

  @override
  String get settingsEnvironmentValueNul =>
      'Значение не может содержать символ NUL.';

  @override
  String get settingsEnvironmentValueTooLong => 'Значение слишком длинное.';

  @override
  String settingsEnvironmentVariablesStatus(int count) {
    return 'Настроено: $count';
  }

  @override
  String get settingsEnvironmentVariablesTitle => 'Настроенные переопределения';

  @override
  String settingsMinutes(int minutes) {
    return '$minutes мин';
  }

  @override
  String get settingsNavigationAbout => 'О Denial';

  @override
  String get settingsNavigationAnimations => 'Анимации';

  @override
  String get settingsNavigationAppearance => 'Оформление';

  @override
  String get settingsNavigationAudio => 'Звук';

  @override
  String get settingsNavigationBluetooth => 'Bluetooth';

  @override
  String get settingsNavigationDesktopLayout => 'Раскладка рабочего стола';

  @override
  String get settingsNavigationDeveloper => 'Для разработчиков';

  @override
  String get settingsNavigationEnvironment => 'Окружение приложений';

  @override
  String get settingsNavigationDisplays => 'Экраны и видео';

  @override
  String get settingsNavigationLanguage => 'Язык';

  @override
  String get settingsNavigationKeyboard => 'Клавиатура';

  @override
  String get settingsNavigationTouchpad => 'Мышь и тачпад';

  @override
  String get settingsNavigationShortcuts => 'Сочетания клавиш';

  @override
  String get settingsNavigationLockScreen => 'Экран блокировки';

  @override
  String get settingsNavigationNetwork => 'Сеть';

  @override
  String get settingsNavigationOverlays => 'Оверлеи';

  @override
  String get settingsNavigationPower => 'Питание';

  @override
  String get settingsNavigationSection => 'Настройки';

  @override
  String get settingsNetworkDescription =>
      'Управляйте Wi-Fi и подключайтесь к ближайшим сетям.';

  @override
  String get settingsNetworkSection => 'Сеть';

  @override
  String get settingsNetworkStatusCaptivePortal => 'Требуется вход';

  @override
  String get settingsNetworkStatusConnecting => 'Подключение…';

  @override
  String get settingsNetworkStatusDisabled => 'Wi-Fi выключен';

  @override
  String get settingsNetworkStatusDisconnected => 'Нет подключения';

  @override
  String get settingsNetworkStatusLimited => 'Ограниченное подключение';

  @override
  String get settingsNetworkStatusLocal => 'Только локальная сеть';

  @override
  String get settingsNetworkStatusOnline => 'В сети';

  @override
  String get settingsNetworkStatusUnavailable => 'Сеть недоступна';

  @override
  String get settingsNetworkTitle => 'Сетевые подключения.';

  @override
  String get settingsNetworkUnavailable => 'Управление сетью недоступно.';

  @override
  String get settingsNoApplicationAudio =>
      'Ни одно приложение не воспроизводит звук.';

  @override
  String get settingsNoBluetoothDevices => 'Устройства Bluetooth не найдены.';

  @override
  String get settingsNoNetworks => 'Сети не найдены.';

  @override
  String get settingsNotificationOverlayDescription =>
      'Расположение баннеров уведомлений.';

  @override
  String get settingsNotificationOverlayTitle => 'Уведомления';

  @override
  String get settingsOneHour => '1 час';

  @override
  String get settingsOuterPadding => 'Внешний отступ';

  @override
  String get settingsOutputVolume => 'Громкость вывода';

  @override
  String get settingsOverlaysDescription =>
      'Выберите положение и размер меню приложений, уведомлений и системных индикаторов.';

  @override
  String get settingsOverlaysSection => 'Оверлеи';

  @override
  String get settingsOverlaysTitle =>
      'Разместите элементы оболочки там, где им место.';

  @override
  String get settingsPaired => 'Сопряжено';

  @override
  String get settingsPanelMotionDescription =>
      'Настройте скорость и дальность движения меню приложений и панели управления.';

  @override
  String get settingsPanelMotionTitle => 'Движение панелей';

  @override
  String get settingsPanelOpacity => 'Непрозрачность панелей';

  @override
  String get settingsPanelTravel => 'Ход панели';

  @override
  String get settingsPasswordRequired => 'Требуется пароль';

  @override
  String settingsPercent(int percent) {
    return '$percent%';
  }

  @override
  String settingsPixels(int pixels) {
    return '$pixels пикс.';
  }

  @override
  String get settingsPowerDescription =>
      'Настройте отключение экрана по таймеру и запрет бездействия.';

  @override
  String get settingsPowerSection => 'Питание';

  @override
  String get settingsPowerTitle => 'Питание, которое не мешает работе.';

  @override
  String get settingsRefresh => 'Обновить';

  @override
  String get settingsResetPage => 'Сбросить страницу';

  @override
  String get settingsScan => 'Поиск';

  @override
  String get settingsScanning => 'Поиск…';

  @override
  String get settingsScreenAnchor => 'Привязка к экрану';

  @override
  String get settingsShapeDescription =>
      'Масштабировать все скругления оболочки, сохраняя иерархию между окнами, панелями, карточками и элементами управления.';

  @override
  String get settingsShapeTitle => 'Форма';

  @override
  String get settingsCornerRoundness => 'Скругление углов';

  @override
  String get settingsColorSchemeTitle => 'Цветовая схема';

  @override
  String get settingsColorSchemeDark => 'Тёмная';

  @override
  String get settingsColorSchemeLight => 'Светлая';

  @override
  String get settingsColorSchemeNoPreference => 'Без предпочтений';

  @override
  String get settingsColorSchemeDescription =>
      'Использовать одну цветовую схему в Denial и поддерживаемых приложениях.';

  @override
  String get settingsColorSchemeNoPreferenceDescription =>
      'Denial сохраняет тёмное оформление по умолчанию, а приложения выбирают сами.';

  @override
  String get settingsShellAccentChoose => 'Выбрать акцентный цвет';

  @override
  String get settingsShellAccentCustom => 'Свой цвет';

  @override
  String get settingsShellAccentDescription =>
      'Акцентным цветом выделяются активные окна, элементы управления и активные части оболочки.';

  @override
  String get settingsShellAccentTitle => 'Акцент оболочки';

  @override
  String get settingsShellAccentWallpaper => 'Из обоев';

  @override
  String get settingsShowSystemStatus =>
      'Показывать производительность и питание';

  @override
  String get settingsShowSystemStatusDescription =>
      'Показывать сведения о ЦП, ГП, батарее и температуре на экране блокировки рабочего стола.';

  @override
  String settingsSignalStrength(int strength) {
    return 'Сигнал: $strength%';
  }

  @override
  String get settingsStorageLocation =>
      'Настройки хранятся в\n~/.config/denial/settings.json';

  @override
  String get settingsSystemBarCloneHint =>
      'У каждого выбранного экрана своя панель. Панель никогда не растягивается на несколько экранов.';

  @override
  String get settingsSystemBarDescription =>
      'Разместите панель у любого края и показывайте независимую копию на каждом выбранном экране.';

  @override
  String settingsSystemBarDisplayDetails(int width, int height, String scale) {
    return '$width × $height · $scale×';
  }

  @override
  String settingsSystemBarDisplayNotSelectedSemantics(String displayName) {
    return 'Системная панель не показывается на $displayName';
  }

  @override
  String settingsSystemBarDisplaySelectedSemantics(String displayName) {
    return 'Системная панель показывается на $displayName';
  }

  @override
  String get settingsSystemBarDisplaysLabel => 'ЭКРАНЫ';

  @override
  String settingsSystemBarDisplaysSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Выбрано $count экрана',
      many: 'Выбрано $count экранов',
      few: 'Выбрано $count экрана',
      one: 'Выбран $count экран',
    );
    return '$_temp0';
  }

  @override
  String get settingsSystemBarEdgeBottom => 'Снизу';

  @override
  String get settingsSystemBarEdgeLabel => 'КРАЙ';

  @override
  String get settingsSystemBarEdgeLeft => 'Слева';

  @override
  String get settingsSystemBarEdgeRight => 'Справа';

  @override
  String get settingsSystemBarEdgeTop => 'Сверху';

  @override
  String get settingsSystemBarLastDisplayHint =>
      'Сначала выберите другой экран, а потом уберите этот.';

  @override
  String get settingsSystemBarMainDisplay => 'ОСНОВНОЙ';

  @override
  String get settingsSystemBarTitle => 'Системная панель рабочего стола';

  @override
  String get settingsSystemBarUnavailable =>
      'Сведения об экранах пока недоступны.';

  @override
  String get settingsTwoHours => '2 часа';

  @override
  String get settingsSuspendTimeout => 'Переходить в сон через';

  @override
  String get settingsUnfocusedWindows => 'Неактивные окна';

  @override
  String get settingsUseSystemWallpaper => 'Использовать системные обои';

  @override
  String get settingsUseSystemWallpaperDescription =>
      'Экран блокировки следует за сменой обоев и их назначением по экранам.';

  @override
  String get settingsWallpaperChoose => 'Изменить';

  @override
  String get settingsWallpaperDescription =>
      'Выберите изображение, которое показывается за оболочкой и на экране блокировки.';

  @override
  String get settingsWallpaperPreviewSemantics => 'Предпросмотр текущих обоев';

  @override
  String get settingsWallpaperTitle => 'Обои';

  @override
  String get settingsWidth => 'Ширина';

  @override
  String get settingsWifiEnabled => 'Wi-Fi включён';

  @override
  String get settingsWifiEnabledDescription =>
      'Разрешить Denial искать беспроводные сети и подключаться к ним.';

  @override
  String get settingsWifiTitle => 'Wi-Fi';

  @override
  String get settingsWindowCloseEffectDescription =>
      'Выберите анимацию закрытия окна.';

  @override
  String get settingsWindowCloseEffectTitle => 'Эффект закрытия окна';

  @override
  String get settingsWindowMinimizationDescription =>
      'Показывать свёрнутые окна живыми миниатюрами на рабочем столе или убирать их за край экрана до восстановления.';

  @override
  String get settingsWindowMinimizationDesktop => 'На рабочем столе';

  @override
  String get settingsWindowMinimizationOffscreen => 'За экраном';

  @override
  String get settingsWindowMinimizationTitle => 'Сворачивание окон';

  @override
  String get settingsWindowOpacityDescription =>
      'Настройте непрозрачность активных и неактивных окон.';

  @override
  String get settingsWindowOpacityTitle => 'Непрозрачность окон';

  @override
  String shortDate(String weekday, int day, String month) {
    return '$weekday, $day $month';
  }

  @override
  String statusBarLiveTime(String time) {
    return '$time · СЕЙЧАС';
  }

  @override
  String get statusUnknown => 'Неизвестно';

  @override
  String get statusWaiting => 'Ожидание';

  @override
  String temperatureCelsius(int temperature) {
    return '$temperature°C';
  }

  @override
  String get thermalSensorCpu => 'ЦП';

  @override
  String get thermalSensorExp2 => 'EXP2';

  @override
  String get thermalSensorPmic => 'PMIC';

  @override
  String get thermalSensorSvooc => 'SVOOC';

  @override
  String timeHoursMinutes(String hour, String minute) {
    return '$hour:$minute';
  }

  @override
  String get valueUnavailable => '--.-';

  @override
  String voltageVolts(String voltage) {
    return '$voltage В';
  }

  @override
  String get volumeTitle => 'Громкость';

  @override
  String get wallpaperAlignBottom => 'Снизу';

  @override
  String get wallpaperAlignHorizontalCenter => 'По центру по горизонтали';

  @override
  String get wallpaperAlignLeft => 'Слева';

  @override
  String get wallpaperAlignRight => 'Справа';

  @override
  String get wallpaperAlignTop => 'Сверху';

  @override
  String get wallpaperAlignVerticalCenter => 'По центру по вертикали';

  @override
  String get wallpaperAllDisplays => 'Все экраны';

  @override
  String get wallpaperApplyAllDisplays => 'Применить ко всем экранам';

  @override
  String wallpaperApplyCandidate(String wallpaperName) {
    return 'Применить $wallpaperName';
  }

  @override
  String wallpaperApplyDisplay(String displayName) {
    return 'Применить к $displayName';
  }

  @override
  String get wallpaperCloseSelector => 'Закрыть выбор обоев';

  @override
  String get wallpaperDarkness => 'Затемнение обоев';

  @override
  String get wallpaperDarknessShort => 'Затемнение';

  @override
  String get wallpaperDecodeError => 'Не удалось декодировать эти обои.';

  @override
  String get wallpaperDefault => 'По умолчанию';

  @override
  String wallpaperDimensions(int width, int height) {
    return '$width × $height';
  }

  @override
  String get wallpaperFinding => 'Поиск обоев…';

  @override
  String wallpaperFolderHint(String directory) {
    return 'Добавляйте свои обои в папку $directory.';
  }

  @override
  String get wallpaperImageServerUnavailable =>
      'Обои из сети недоступны. Локальные обои по-прежнему работают.';

  @override
  String get wallpaperPreviousPage => 'Предыдущая страница обоев';

  @override
  String get wallpaperNextPage => 'Следующая страница обоев';

  @override
  String wallpaperPageNumber(int page) {
    return 'Страница $page';
  }

  @override
  String wallpaperPageOfTotal(int page, int total) {
    return 'Страница $page из $total';
  }

  @override
  String get wallpaperLayout => 'Вид предпросмотра';

  @override
  String get wallpaperLayoutGallery => 'Галерея';

  @override
  String get wallpaperLayoutGalleryDescription => 'Показывать обои целиком';

  @override
  String get wallpaperLayoutStrips => 'Полосы';

  @override
  String get wallpaperLayoutStripsDescription =>
      'Показывать обрезанные полосы обоев';

  @override
  String get wallpaperMobileBackToSelection => 'Назад к выбору обоев';

  @override
  String get wallpaperMobileCenterPosition => 'По центру';

  @override
  String get wallpaperMobileChoose => 'Выберите обои';

  @override
  String get wallpaperMobileDone => 'Готово';

  @override
  String get wallpaperMobileHideControls => 'Скрыть элементы управления';

  @override
  String get wallpaperMobileHorizontalPosition => 'По горизонтали';

  @override
  String get wallpaperMobilePosition => 'Положение';

  @override
  String get wallpaperMobilePositionHint =>
      'Перетащите обои, затем уточните положение';

  @override
  String get wallpaperMobileShowControls => 'Показать элементы управления';

  @override
  String get wallpaperMobileTitle => 'Обои';

  @override
  String get wallpaperMobileVerticalPosition => 'По вертикали';

  @override
  String get wallpaperNoneFound => 'Обои не найдены';

  @override
  String get wallpaperSearchHint => 'Поиск обоев';

  @override
  String get wallpaperSearchSemantics => 'Поиск обоев';

  @override
  String get wallpaperServiceUnavailable => 'Служба обоев недоступна';

  @override
  String get wallpaperSpanAlignment => 'Положение изображения';

  @override
  String get wallpaperTarget => 'Где применить';

  @override
  String get weekdayFriday => 'Пятница';

  @override
  String get weekdayMonday => 'Понедельник';

  @override
  String get weekdaySaturday => 'Суббота';

  @override
  String get weekdaySunday => 'Воскресенье';

  @override
  String get weekdayThursday => 'Четверг';

  @override
  String get weekdayTuesday => 'Вторник';

  @override
  String get weekdayWednesday => 'Среда';

  @override
  String get wifiAuthorizationMayBeRequired =>
      'Может потребоваться авторизация.';

  @override
  String get wifiCloseDetails => 'Закрыть сведения о Wi-Fi';

  @override
  String wifiConnectNetwork(String networkName, String status, int strength) {
    return 'Подключиться к $networkName, $status, сигнал $strength%';
  }

  @override
  String wifiDisconnectNetwork(String networkName) {
    return 'Отключиться от $networkName';
  }

  @override
  String get wifiDismissError => 'Закрыть ошибку Wi-Fi';

  @override
  String wifiForgetNetwork(String networkName) {
    return 'Забыть сеть $networkName';
  }

  @override
  String get wifiHardwareBlocked => 'Wi-Fi заблокирован аппаратно';

  @override
  String get wifiHardwareBlockedDescription =>
      'Включите аппаратный переключатель беспроводной связи, чтобы продолжить.';

  @override
  String get wifiHardwareDisabled => 'Модуль Wi-Fi отключён';

  @override
  String get wifiLimitedConnection => 'Ограниченное подключение';

  @override
  String get wifiLoadingService => 'Загрузка сетевой службы…';

  @override
  String get wifiLocalConnection => 'Локальная сеть';

  @override
  String get wifiLocalOnly => 'Только локальная';

  @override
  String wifiNamedStatus(String networkName, String status) {
    return '$networkName · $status';
  }

  @override
  String get wifiNoAdapter => 'Нет адаптера Wi-Fi';

  @override
  String get wifiNoAdapterDescription =>
      'Управление Wi-Fi появится, когда будет доступен адаптер.';

  @override
  String get wifiNoNetworks => 'Сети не найдены';

  @override
  String get wifiNoNetworksDescription =>
      'Запустите поиск, чтобы найти ближайшие сети.';

  @override
  String get wifiOff => 'Wi-Fi выключен';

  @override
  String get wifiOffDescription => 'Включите, чтобы увидеть ближайшие сети.';

  @override
  String get wifiOperationFailed => 'Не удалось выполнить запрос Wi-Fi.';

  @override
  String wifiPasswordField(String networkName) {
    return 'Пароль для $networkName';
  }

  @override
  String wifiPasswordFor(String networkName) {
    return 'Введите пароль для $networkName';
  }

  @override
  String get wifiPasswordRequirements =>
      'Введите пароль длиной не менее 8 символов.';

  @override
  String get wifiPermissionLimited => 'Права на управление сетью ограничены.';

  @override
  String get wifiSavedOutOfRange => 'Сохранена · вне зоны действия';

  @override
  String wifiSavedWithSecurity(String security) {
    return 'Сохранена · $security';
  }

  @override
  String get wifiScanNetworks => 'Искать сети Wi-Fi';

  @override
  String get wifiScanningDescription =>
      'Ближайшие сети появятся автоматически.';

  @override
  String get wifiScanningNetworks => 'Поиск сетей Wi-Fi…';

  @override
  String get wifiSecurityEnhancedOpen => 'Enhanced Open';

  @override
  String get wifiSecurityEnterprise => 'Enterprise';

  @override
  String get wifiSecurityOpen => 'Открытая';

  @override
  String get wifiSecurityUnsupported => 'Неподдерживаемая защита';

  @override
  String get wifiSecurityWep => 'WEP';

  @override
  String get wifiSecurityWpa3Personal => 'WPA3 Personal';

  @override
  String get wifiSecurityWpaPersonal => 'WPA/WPA2 Personal';

  @override
  String get wifiServiceUnavailable => 'Сетевая служба недоступна';

  @override
  String get wifiServiceUnavailableDescription =>
      'Управление Wi-Fi вернётся, когда сетевая служба запустится.';

  @override
  String get wifiServiceUnavailableShort => 'Сеть недоступна';

  @override
  String get wifiSignInRequired => 'Требуется вход';

  @override
  String get wifiTurnOff => 'Выключить Wi-Fi';

  @override
  String get wifiTurnOn => 'Включить Wi-Fi';

  @override
  String get wifiWepRequirements =>
      'Ключ WEP должен содержать от 5 до 64 символов.';

  @override
  String windowSwitcherPosition(int position, int total) {
    return '$position / $total';
  }

  @override
  String windowSwitcherSelected(String windowTitle) {
    return 'Выбрано: $windowTitle';
  }

  @override
  String windowUntitled(int windowId) {
    return 'Окно $windowId';
  }

  @override
  String get settingsGlassAdvanced => 'Настройка стекла';

  @override
  String get settingsGlassReset => 'Сбросить стекло';

  @override
  String get settingsGlassTuningDescription =>
      'Изменения применяются сразу. Значения по умолчанию сохраняют исходный эффект стекла.';

  @override
  String get settingsGlassBevelWidth => 'Ширина фаски';

  @override
  String get settingsGlassRefractionDepth => 'Глубина преломления';

  @override
  String get settingsGlassRimWidth => 'Ширина блика';

  @override
  String get settingsGlassRimFalloff => 'Спад блика';

  @override
  String get settingsGlassOppositeLight => 'Свет на противоположном крае';

  @override
  String settingsGlassRimPixels(String width) {
    return '$width пикс.';
  }

  @override
  String get lockFingerprintNotRecognized => 'Отпечаток не распознан';

  @override
  String get fingerprintSection => 'Отпечаток пальца';

  @override
  String get fingerprintPinPrompt =>
      'Введите PIN-код блокировки, чтобы управлять отпечатками.';

  @override
  String get fingerprintPin => 'PIN-код';

  @override
  String get fingerprintContinue => 'Продолжить';

  @override
  String get fingerprintDescription =>
      'Разблокируйте Denial добавленными отпечатками пальцев.';

  @override
  String get fingerprintEmptyTitle => 'Отпечатки не добавлены';

  @override
  String get fingerprintEmptyDescription =>
      'Выберите палец ниже, чтобы добавить первый отпечаток.';

  @override
  String get fingerprintChooseFinger => 'Палец для отпечатка';

  @override
  String get fingerprintEnroll => 'Добавить отпечаток';

  @override
  String get fingerprintAdd => 'Добавить отпечаток';

  @override
  String get fingerprintPinNotSet => 'Сначала задайте PIN-код блокировки.';

  @override
  String get fingerprintExpired => 'Введите PIN-код ещё раз, чтобы продолжить.';

  @override
  String get fingerprintPreparing => 'Подготовка сканера отпечатков…';

  @override
  String get fingerprintTouchSensor =>
      'Прикладывайте выбранный палец к сканеру и поднимайте его.';

  @override
  String get fingerprintEnrolled =>
      'Отпечаток добавлен. Теперь им можно разблокировать Denial.';

  @override
  String get fingerprintCancelled => 'Добавление отменено.';

  @override
  String get fingerprintDuplicate =>
      'Этот отпечаток уже добавлен. Выберите другой палец.';

  @override
  String get fingerprintRetry =>
      'Поднимите палец и приложите его снова, немного изменив положение.';

  @override
  String get fingerprintUnavailable =>
      'Не удалось выполнить операцию с отпечатками. Проверьте сканер и повторите попытку.';

  @override
  String fingerprintProgress(int completed, int total) {
    return 'Касание $completed из $total';
  }

  @override
  String get fingerprintLeftThumb => 'Левый большой палец';

  @override
  String get fingerprintLeftIndex => 'Левый указательный палец';

  @override
  String get fingerprintLeftMiddle => 'Левый средний палец';

  @override
  String get fingerprintLeftRing => 'Левый безымянный палец';

  @override
  String get fingerprintLeftLittle => 'Левый мизинец';

  @override
  String get fingerprintRightThumb => 'Правый большой палец';

  @override
  String get fingerprintRightIndex => 'Правый указательный палец';

  @override
  String get fingerprintRightMiddle => 'Правый средний палец';

  @override
  String get fingerprintRightRing => 'Правый безымянный палец';

  @override
  String get fingerprintRightLittle => 'Правый мизинец';

  @override
  String get mobileData => 'Мобильный интернет';

  @override
  String get mobileConnected => 'Подключено';

  @override
  String get mobileDisconnected => 'Не подключено';

  @override
  String get mobileUnavailable => 'Мобильная сеть недоступна';

  @override
  String get mobileChangeFailed =>
      'Не удалось изменить настройку мобильного интернета';

  @override
  String get simPinTitle => 'Разблокировка SIM-карты';

  @override
  String get simPinUnlock => 'Разблокировать';

  @override
  String get simPinLater => 'Позже';

  @override
  String get simPukRequired =>
      'Для SIM-карты нужен PUK-код. Обратитесь к оператору.';

  @override
  String get simLocked => 'SIM-карта заблокирована';

  @override
  String simPinRetries(int count) {
    return 'Осталось попыток: $count';
  }

  @override
  String get settingsShortcutActionResizeGrowWidth => 'Увеличить ширину окна';

  @override
  String get settingsShortcutActionResizeShrinkWidth => 'Уменьшить ширину окна';

  @override
  String get settingsShortcutActionResizeGrowHeight => 'Увеличить высоту окна';

  @override
  String get settingsShortcutActionResizeShrinkHeight =>
      'Уменьшить высоту окна';

  @override
  String get settingsShortcutActionResetWindowHeight => 'Сбросить высоту окна';

  @override
  String get settingsShortcutActionResetWindowWidth => 'Сбросить ширину окна';

  @override
  String get settingsAppearanceTheme => 'Тема';

  @override
  String get settingsAppearanceWindows => 'Окна';

  @override
  String get settingsAppearanceTransparency => 'Прозрачность';

  @override
  String get settingsAppearanceAdvancedEffects => 'Дополнительные эффекты';

  @override
  String get settingsAppearanceAdvancedEffectsDescription =>
      'Цвет, оптика, освещение и отрисовка.';

  @override
  String get settingsAppearanceCompositingDescription =>
      'Уточните, где применяется эффект.';

  @override
  String get settingsAppearanceColorEffects => 'Цвет';

  @override
  String get settingsAppearanceOptics => 'Оптика';

  @override
  String get settingsAppearanceLighting => 'Освещение';

  @override
  String get settingsAppearanceRendering => 'Отрисовка';

  @override
  String get settingsAppearanceCursorAdvanced => 'Курсоры приложений';

  @override
  String get settingsAppearanceActions => 'Действия с оформлением';

  @override
  String get settingsResetAppearance => 'Сбросить оформление';

  @override
  String get settingsResetGlassEffects => 'Сбросить эффекты стекла';

  @override
  String get settingsWallpaperDefault => 'Стандартные обои Denial';

  @override
  String get settingsWallpaperLive => 'Живые обои / обои приложения';

  @override
  String get settingsWallpaperStatic => 'Статичные обои';

  @override
  String get settingsWallpaperLiveDescription =>
      'Этот рабочий стол рисует приложение обоев. Выбор запасного изображения его не остановит.';

  @override
  String get settingsWallpaperChooseFallback => 'Выбрать запасное изображение';

  @override
  String get settingsWallpaperPreviewUnavailable => 'Предпросмотр недоступен';

  @override
  String get settingsWallpaperFallback => 'Запасное изображение';

  @override
  String settingsWallpaperDisplay(String name) {
    return 'Экран · $name';
  }

  @override
  String get settingsWallpaperApplied => 'Установленные обои';

  @override
  String get settingsShortcutProviderUnavailable => 'Источник недоступен';

  @override
  String get welcomeStart => 'Знакомство';

  @override
  String get welcomeGetStarted => 'Начать';

  @override
  String get welcomeStartDescription =>
      'Располагайтесь. Мы покажем основные сочетания клавиш, поможем выбрать раскладку окон и настроить рабочий стол под себя. Всё это можно изменить позже в настройках.';

  @override
  String get welcomeTitle => 'Добро пожаловать в Denial';

  @override
  String get welcomeShortcuts => 'Сочетания клавиш';

  @override
  String get welcomeLayout => 'Раскладка';

  @override
  String get welcomeAppearance => 'Оформление';

  @override
  String get welcomeSupport => 'Поддержка';

  @override
  String get welcomeNext => 'Далее';

  @override
  String get welcomePrevious => 'Назад';

  @override
  String get welcomeFinish => 'Начать работу с Denial';

  @override
  String get welcomeExitSetup => 'Выйти из настройки';

  @override
  String get welcomeExit => 'Выйти';

  @override
  String get welcomeCancel => 'Отмена';

  @override
  String get welcomeExitMessage =>
      'Настройка больше не появится сама; её можно открыть из меню приложений.';

  @override
  String get welcomeIntro =>
      'Другой рабочий стол. Несколько клавиш — и он ваш.';

  @override
  String get welcomeShortcutsDescription =>
      'Это ваши текущие сочетания клавиш. Их можно изменить позже: Настройки → Сочетания клавиш.';

  @override
  String get welcomeKill => 'Закрыть активное окно';

  @override
  String get welcomeMove => 'Переместить окно';

  @override
  String get welcomeResize => 'Изменить размер окна';

  @override
  String get welcomeMoveGesture => 'Super + перетаскивание левой кнопкой';

  @override
  String get welcomeResizeGesture => 'Super + перетаскивание правой кнопкой';

  @override
  String get welcomePointerHint =>
      'Удерживайте Super (клавишу Windows) и тяните за любое место окна. Эти жесты указателя встроены.';

  @override
  String get welcomeUnbound => 'Не назначено';

  @override
  String get welcomeRetry => 'Повторить';

  @override
  String get welcomeShortcutsError => 'Не удалось загрузить сочетания клавиш.';

  @override
  String get welcomeLayoutTitle => 'Место для вашего стиля работы.';

  @override
  String get welcomeInstant =>
      'Попробуйте вариант. Рабочий стол меняется сразу.';

  @override
  String get welcomeStackingDescription =>
      'Свободно размещайте и перекрывайте окна.';

  @override
  String get welcomeDwindleDescription =>
      'Окна укладываются в сбалансированную ветвящуюся мозаику.';

  @override
  String get welcomeScrollingDescription =>
      'Плавная лента окон, которую можно продолжать сколько угодно.';

  @override
  String get welcomeAppearanceTitle => 'Рабочий стол в вашем стиле.';

  @override
  String get welcomeMaterial => 'Материал окон';

  @override
  String get welcomeGlass => 'Стекло';

  @override
  String get welcomeBlur => 'Размытие';

  @override
  String get welcomeNothing => 'Нет';

  @override
  String get welcomeTheme => 'Тема';

  @override
  String get welcomeLight => 'Светлая';

  @override
  String get welcomeDark => 'Тёмная';

  @override
  String get welcomeSupportTitle =>
      'Помогите Denial стать тем, что будет дальше.';

  @override
  String get welcomeSupportDescription =>
      'Denial создаётся с заботой, любопытством и верой в то, что рабочий стол может быть другим. Если вам здесь как дома, ваша поддержка помогает ему расти.';

  @override
  String get welcomeSupportOptional =>
      'Всегда по желанию. Спасибо, что нашли для Denial место на своём рабочем столе.';

  @override
  String get welcomeDonate => 'Пожертвовать';

  @override
  String get welcomeSponsors => 'GitHub Sponsors';

  @override
  String get welcomeRepository => 'Denial на GitHub';

  @override
  String get welcomeLinksPending => 'Ссылки для пожертвований скоро появятся.';

  @override
  String get welcomeLinkError =>
      'Не удалось открыть браузер. Повторите попытку.';

  @override
  String get welcomeSaveError =>
      'Не удалось сохранить завершение настройки. Повторите попытку.';

  @override
  String get welcomeWorkspaceDisabled =>
      'Рабочие пространства сейчас выключены. Чтобы пользоваться этими сочетаниями, включите их: Настройки → Раскладка рабочего стола.';

  @override
  String get welcomeDesktopUsage => 'Основы рабочего стола';

  @override
  String get welcomeWorkspaces => 'Рабочие пространства';

  @override
  String get welcomeTiling => 'Мозаика и управление с клавиатуры';

  @override
  String get polkitRunCommandAsAdministrator =>
      'Требуется аутентификация администратора.';

  @override
  String polkitRunCommandAsUser(String user) {
    return 'Для запуска этой команды от имени $user требуется аутентификация.';
  }

  @override
  String get polkitAuthenticationRequired => 'Требуется аутентификация.';

  @override
  String get polkitAuthenticationUnavailable => 'Аутентификация недоступна.';

  @override
  String get polkitPassword => 'Пароль';

  @override
  String get polkitVerifying => 'Проверка…';

  @override
  String get polkitPreparing => 'Подготовка…';

  @override
  String get polkitCapsLock => 'Caps Lock';

  @override
  String get polkitConfirm => 'Подтвердить';

  @override
  String get polkitContinue => 'Продолжить';

  @override
  String get polkitClose => 'Закрыть';

  @override
  String get polkitLocked => 'Временно заблокировано';

  @override
  String get accessAllow => 'Разрешить';

  @override
  String get accessAllowOnce => 'Разрешить один раз';

  @override
  String get accessAlwaysAllow => 'Разрешать всегда';

  @override
  String get accessDecline => 'Отклонить';

  @override
  String get accessNeverAllow => 'Никогда не разрешать';

  @override
  String get accessDeclineOnce => 'Отклонить один раз';

  @override
  String get accessUnknownApp => 'Приложение';

  @override
  String get pluginsAppTitle => 'Плагины Denial';

  @override
  String get pluginsTitle => 'Плагины';

  @override
  String get pluginsInstalled => 'Установленные';

  @override
  String get pluginsDiscover => 'Обзор';

  @override
  String get pluginsActivity => 'Активность';

  @override
  String get pluginsLibrary => 'Библиотека';

  @override
  String get pluginsPreferences => 'Параметры';

  @override
  String get pluginsSearchInstalled => 'Поиск среди установленных';

  @override
  String get pluginsSearch => 'Поиск плагинов';

  @override
  String get pluginsClearSearch => 'Очистить поиск';

  @override
  String get pluginsAddTooltip => 'Добавить плагин по ссылке на репозиторий';

  @override
  String get pluginsAddToolbar => 'Добавить плагин';

  @override
  String get pluginsMoreActions => 'Другие действия';

  @override
  String get pluginsRefresh => 'Обновить';

  @override
  String get pluginsInstalledTitle => 'Установленные плагины';

  @override
  String get pluginsInstalledDescription =>
      'Выберите плагины, из которых состоит ваш рабочий стол.';

  @override
  String get pluginsNoneInstalled => 'Плагины не установлены';

  @override
  String get pluginsNoneInstalledDescription =>
      'Найдите плагины для рабочего стола или добавьте плагин по ссылке на репозиторий.';

  @override
  String get pluginsDiscoverAction => 'Найти плагины';

  @override
  String get pluginsUseDefaults => 'Стандартный набор Denial';

  @override
  String get pluginsNoMatches => 'Подходящих плагинов нет';

  @override
  String get pluginsNoMatchesDescription =>
      'Попробуйте другое название или очистите поиск.';

  @override
  String get pluginsAutomaticTitle => 'Добавлены автоматически';

  @override
  String get pluginsAutomaticDescription =>
      'Они нужны для работы выбранных плагинов.';

  @override
  String get pluginsDiscoverMore => 'Найти ещё плагины';

  @override
  String get pluginsPreparingDesktop => 'Подготовка рабочего стола';

  @override
  String get pluginsPreparingDescription =>
      'Denial всё подготавливает. Можно оставить это окно открытым или вернуться позже.';

  @override
  String get pluginsTryAgain => 'Повторить';

  @override
  String get pluginsFallbackDescription =>
      'Настройте рабочий стол с помощью этого плагина.';

  @override
  String get pluginsSelected => 'Выбран';

  @override
  String get pluginsNotSelected => 'Не выбран';

  @override
  String get pluginsDesktopOptions => 'Параметры рабочего стола';

  @override
  String get pluginsDesktopOptionsDescription =>
      'Обновления, совместимость и восстановление';

  @override
  String get pluginsCheckUpdates => 'Проверить обновления плагинов';

  @override
  String get pluginsCheckCompatibility => 'Проверить совместимость';

  @override
  String get pluginsUndo => 'Отменить последнее изменение';

  @override
  String get pluginsRestore => 'Восстановить стандартный рабочий стол';

  @override
  String get pluginsCheckSelection => 'Проверьте выбор';

  @override
  String get pluginsStartupFailed => 'Не удалось запустить сохранённые плагины';

  @override
  String get pluginsChangeFailed => 'Не удалось завершить изменение';

  @override
  String get pluginsSelectionChanged => 'Ваш выбор изменился';

  @override
  String get pluginsPaused => 'Плагины приостановлены';

  @override
  String get pluginsPendingReady => 'Отложенные действия готовы';

  @override
  String get pluginsPreparingSupport => 'Подготовка поддержки плагинов';

  @override
  String get pluginsViewDetails => 'Подробнее';

  @override
  String get pluginsDiscard => 'Отменить';

  @override
  String get pluginsSwitchNow => 'Переключить сейчас';

  @override
  String get pluginsDismissError => 'Закрыть ошибку';

  @override
  String get pluginsInProgress => 'Выполняется';

  @override
  String get pluginsDiscoverTitle => 'Обзор плагинов';

  @override
  String get pluginsDiscoverDescription =>
      'Добавляйте новые возможности и настраивайте рабочий стол под себя.';

  @override
  String get pluginsNothingFound => 'Пока ничего не найдено';

  @override
  String get pluginsNothingFoundDescription =>
      'Попробуйте другой запрос или добавьте плагин по ссылке на его репозиторий.';

  @override
  String get pluginsOfficial => 'Сделано для Denial';

  @override
  String get pluginsCommunity => 'От сообщества';

  @override
  String get pluginsRefreshDiscoveries => 'Обновить список';

  @override
  String get pluginsNoCommunity =>
      'Плагинов от сообщества пока нет. Добавьте плагин по ссылке на его репозиторий.';

  @override
  String get pluginsAddRepository => 'Добавить из репозитория';

  @override
  String get pluginsAddRepositoryDescription =>
      'Установите плагин от разработчика по ссылке Git.';

  @override
  String get pluginsAddLink => 'Добавить по ссылке';

  @override
  String get pluginsDiscoveryFailed =>
      'Часть списка не удалось загрузить. Попробуйте обновить ещё раз.';

  @override
  String get pluginsByDenial => 'От Denial';

  @override
  String get pluginsCommunityPlugin => 'Плагин сообщества';

  @override
  String get pluginsSelectedDesktop => 'Выбран для рабочего стола';

  @override
  String get pluginsSelect => 'Выбрать плагин';

  @override
  String get pluginsRecentActivity => 'Недавняя активность';

  @override
  String get pluginsActivityDescription =>
      'Ход установки и изменения рабочего стола.';

  @override
  String get pluginsNoActivity => 'Пока нет активности';

  @override
  String get pluginsNoActivityDescription =>
      'Здесь появятся установки плагинов и изменения рабочего стола.';

  @override
  String get pluginsCompleted => 'Завершено';

  @override
  String get pluginsNeedsAttention => 'Требует внимания';

  @override
  String get pluginsNoCandidates =>
      'В этом репозитории не найдено пакетов плагинов.';

  @override
  String get pluginsBringNew => 'Добавьте что-то новое.';

  @override
  String get pluginsTrustDescription =>
      'Вставьте ссылку на репозиторий, чтобы найти его плагины. Плагины становятся частью рабочего стола, поэтому выбирайте код, которому доверяете.';

  @override
  String get pluginsLocalDirectory =>
      'Локальный каталог пакета или репозитория';

  @override
  String get pluginsRepositoryLink => 'Ссылка на репозиторий';

  @override
  String get pluginsAdvancedOptions => 'Дополнительные параметры';

  @override
  String get pluginsGitRef => 'Ветка, тег или коммит (необязательно)';

  @override
  String get pluginsLocalDevelopment => 'Локальная разработка';

  @override
  String get pluginsUseLocal => 'Использовать локальную рабочую копию';

  @override
  String get pluginsChoose => 'Выберите плагин';

  @override
  String get pluginsIncludeDependencies =>
      'Всё, что нужно этому плагину, будет добавлено автоматически.';

  @override
  String get pluginsFinding => 'Поиск плагинов…';

  @override
  String get pluginsFind => 'Найти плагины';

  @override
  String get pluginsAdd => 'Добавить плагин';

  @override
  String get pluginsYourPlugins => 'Ваши плагины';

  @override
  String get pluginsLogLoadFailed => 'Не удалось загрузить журнал сборки.';

  @override
  String get pluginsTechnicalDetails => 'Технические сведения';

  @override
  String get pluginsBuildLog => 'Журнал сборки';

  @override
  String get pluginsNoBuildOutput => 'Вывод сборки не записан.';

  @override
  String get pluginsClose => 'Закрыть';

  @override
  String get pluginsDone => 'Готово';

  @override
  String get pluginsApply => 'Применить плагины';

  @override
  String get pluginsBuild => 'Собрать плагины';

  @override
  String get pluginsCheckChanges => 'Проверьте изменения';

  @override
  String get pluginsEnable => 'Включить плагин';

  @override
  String get pluginsDisable => 'Выключить плагин';

  @override
  String get pluginsUpdate => 'Обновить плагины';

  @override
  String get pluginsRebuild => 'Пересобрать плагины';

  @override
  String get pluginsSetup => 'Настроить плагины';

  @override
  String get pluginsChooseDefaults => 'Выбрать стандартные плагины';

  @override
  String get pluginsActivityFallback => 'Активность плагинов';

  @override
  String get pluginsWorking => 'Изменения применяются';

  @override
  String get pluginsApplyChanges => 'Применить изменения';

  @override
  String get pluginsApplyPending => 'Применить отложенные действия';

  @override
  String get pluginsApplySelectionUpdates =>
      'Применить к рабочему столу изменения выбора и ожидающие обновления.';

  @override
  String get pluginsApplySelection =>
      'Применить к рабочему столу изменения в выборе плагинов.';

  @override
  String get pluginsApplyUnchanged =>
      'Переключатели не изменились. Ожидающие обновления плагинов нужно применить к рабочему столу.';

  @override
  String get pluginsStaleSelection =>
      'Выбор был изменён в другом месте. Отмените черновик, чтобы загрузить актуальный выбор.';

  @override
  String get pluginsUpdated => 'Denial обновлён.';

  @override
  String get pluginsFailureVersion =>
      'Сохранённые плагины собраны для другой версии Denial. Пересоберите их подходящими установленными инструментами сборки.';

  @override
  String get pluginsFailurePanel =>
      'Выбрано больше одной панели рабочего стола. Оставьте включённой одну и примените снова.';

  @override
  String get pluginsFailureConflict =>
      'Несколько плагинов предоставляют одну и ту же функцию. Выберите один и примените снова. Конфликтующие плагины указаны в подробностях.';

  @override
  String get pluginsFailureMissing =>
      'Не хватает обязательной функции рабочего стола. Включите плагин, который её предоставляет, и примените снова.';

  @override
  String get pluginsFailureLogin =>
      'Выйдите из Denial и войдите снова, чтобы завершить обновление. Ваш выбор сохранён.';

  @override
  String get pluginsFailureWorker =>
      'Фоновая операция неожиданно остановилась. Загляните в «Активность», прежде чем повторять.';

  @override
  String get pluginsFailureDownload =>
      'Не удалось выполнить загрузку. Проверьте подключение и повторите попытку.';

  @override
  String get pluginsFailureGeneric =>
      'Не удалось завершить это изменение. Откройте подробности, чтобы узнать причину.';

  @override
  String get pluginsToolsUnavailable =>
      'Инструменты плагинов временно недоступны. Повтор выполняется автоматически.';

  @override
  String get pluginsDartCompatible => 'Требуется совместимая версия Dart';

  @override
  String get pluginsDartRequired => 'Требуется Dart';

  @override
  String get pluginsToolsAttention => 'Инструменты плагинов требуют внимания';

  @override
  String get pluginsSetupFailed =>
      'Не удалось завершить подготовку. Подробности — в «Активности»; затем повторите попытку.';

  @override
  String get pluginsWaitingStart => 'Ожидание запуска';

  @override
  String get pluginsCloseWhileWorking =>
      'Это окно можно закрыть. Работа продолжится.';

  @override
  String get pluginsPreparingPlugins => 'Подготовка плагинов';

  @override
  String get pluginsCheckingCompatibility => 'Проверка совместимости плагинов';

  @override
  String get pluginsPreparingBuild => 'Подготовка сборки рабочего стола';

  @override
  String get pluginsCompilingSources => 'Компиляция исходного кода Dart';

  @override
  String get pluginsOptimizing => 'Оптимизация и генерация машинного кода';

  @override
  String get pluginsPreparingAssets => 'Подготовка ресурсов';

  @override
  String get pluginsLoadingDesktop => 'Загрузка сохранённого рабочего стола';

  @override
  String get pluginsCompilingDesktop => 'Компиляция рабочего стола';

  @override
  String get pluginsVerifyingDesktop => 'Проверка рабочего стола';

  @override
  String get pluginsSwitchingPause => 'Переключение, когда вы сделаете паузу';

  @override
  String get pluginsApplyingDesktop => 'Применение и проверка рабочего стола';

  @override
  String get pluginsVerifyingTools => 'Проверка инструментов плагинов';

  @override
  String get pluginsPreparingTools => 'Подготовка инструментов плагинов';

  @override
  String get pluginsConfigurationDescription =>
      'Выберите плагины из библиотеки, а затем примените все изменения разом. Denial сам подготовит всё, что нужно рабочему столу.\n\nПлагины можно добавлять и по ссылке на репозиторий. Прежние рабочие варианты рабочего стола остаются доступны в меню рабочего стола.';

  @override
  String pluginsSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Выбрано $count',
      many: 'Выбрано $count',
      few: 'Выбрано $count',
      one: 'Выбран $count',
      zero: 'Ничего не выбрано',
    );
    return '$_temp0';
  }

  @override
  String pluginsSwitchSemantics(String name) {
    return 'Плагин $name';
  }

  @override
  String pluginsCandidateLabel(String name, String path) {
    return '$name · $path';
  }

  @override
  String pluginsStepsComplete(int completed, int total) {
    return 'Выполнено шагов: $completed из $total';
  }

  @override
  String pluginsStep(int step, int total, String label) {
    return 'Шаг $step из $total · $label';
  }

  @override
  String pluginsElapsed(String stage, String clock) {
    return '$stage · прошло $clock';
  }

  @override
  String pluginsInstalledVersion(String version) {
    return 'Установлен Denial $version.';
  }

  @override
  String pluginsRebuildDescription(String introduction) {
    return '$introduction Пересоберите плагины, чтобы вернуть их со всеми настройками. Выходить из сеанса не нужно.';
  }

  @override
  String pluginsDartIncompatible(String installed, String constraint) {
    return 'Установлен Dart $installed, а Denial требует $constraint. Установите совместимый пакет Dart, убедитесь, что dart доступен в PATH, и повторите попытку.';
  }

  @override
  String pluginsDartInstall(String expected) {
    return 'Установите Dart системным менеджером пакетов. Denial рекомендует Dart $expected. Убедитесь, что dart доступен в PATH, и повторите попытку.';
  }

  @override
  String pluginsProviderConflict(
    String feature,
    String plugins,
    String owner,
    int maximum,
  ) {
    return 'Функцию «$feature» предоставляют: $plugins. Для «$owner» допустимо поставщиков: не более $maximum. Выключите лишние плагины перед применением.';
  }

  @override
  String pluginsProviderMissing(String owner, int minimum, String feature) {
    return 'Для «$owner» нужно поставщиков функции «$feature»: не менее $minimum. Включите совместимый плагин перед применением.';
  }

  @override
  String pluginsInvalidDeclaration(String plugins) {
    return 'Недопустимые объявления совместимости: $plugins. Откройте подробности, чтобы узнать причину.';
  }

  @override
  String get pluginsFailureDeclaration =>
      'Сведения о совместимости плагинов требуют внимания. Проверьте выбор и откройте подробности, прежде чем применять снова.';

  @override
  String get pluginsDesktopFeature => 'Рабочий стол';

  @override
  String get inputDeckTitle => 'Экран как клавиатура и тачпад';

  @override
  String get inputDeckHeading => 'Клавиатура и тачпад';

  @override
  String get inputDeckEnable =>
      'Использовать сенсорный экран как клавиатуру и тачпад';

  @override
  String get inputDeckUnavailable =>
      'Подключите сенсорный экран, чтобы настроить этот режим.';

  @override
  String inputDeckEnableDescription(String output) {
    return 'Использовать $output для ввода, когда доступен другой экран. Отключите внешний экран, чтобы вернуться в режим планшета.';
  }

  @override
  String get inputDeckWaiting =>
      'Заработает, когда второй экран будет подключён и включён.';

  @override
  String get inputDeckTouchDisplay => 'Сенсорный экран';

  @override
  String get inputDeckTouchDisplayDescription =>
      'Экран, который служит клавиатурой и тачпадом.';

  @override
  String get inputDeckKeyboardSize => 'Размер клавиатуры';

  @override
  String get inputDeckTouchpadWidth => 'Ширина тачпада';

  @override
  String get inputDeckTouchpadHeight => 'Высота тачпада';

  @override
  String get inputDeckPointerSpeed => 'Скорость указателя';

  @override
  String get inputDeckNaturalScroll => 'Естественная прокрутка';

  @override
  String get inputDeckNaturalScrollDescription =>
      'Содержимое следует за движением пальцев.';

  @override
  String get inputDeckCpuChart => 'График ЦП';

  @override
  String get inputDeckCpuDescription =>
      'Показывать загрузку процессора над клавиатурой.';

  @override
  String get inputDeckGpuCharts => 'Графики ГП';

  @override
  String get inputDeckGpuDescription =>
      'Показывать загрузку тех ГП, которые её сообщают.';

  @override
  String get inputDeckUseAsDisplay => 'Использовать как экран';

  @override
  String get inputDeckTouchpad => 'Тачпад';

  @override
  String get inputDeckTouchpadHint =>
      'Тачпад. Один палец двигает указатель. Касание — нажатие. Два пальца — прокрутка, касание двумя — правая кнопка. Двойное касание с удержанием — перетаскивание.';

  @override
  String get inputDeckLeftClick => 'Левая кнопка';

  @override
  String get inputDeckRightClick => 'Правая кнопка';

  @override
  String get lockEnterPin => 'Введите PIN-код';

  @override
  String lockEnterPinToOpen(String applicationName) {
    return 'Введите PIN-код, чтобы открыть $applicationName';
  }

  @override
  String lockPinProgress(int entered, int length) {
    return 'PIN-код, введено цифр: $entered из $length';
  }

  @override
  String get lockPinObscured => 'PIN-код, скрыт';

  @override
  String get lockWrongPin => 'Неверный PIN-код';

  @override
  String get lockUsePassword => 'Ввести пароль';

  @override
  String get lockUsePin => 'Ввести PIN-код';

  @override
  String get lockPinDelete => 'Удалить';

  @override
  String get settingsLockPinTitle => 'PIN-код';

  @override
  String get settingsLockPinLabel => 'Разблокировка PIN-кодом';

  @override
  String get settingsLockPinDescription =>
      'Вводите на экране блокировки короткий цифровой PIN-код вместо пароля. Пароль тоже разблокирует, а во всех остальных случаях по-прежнему нужен он.';

  @override
  String settingsLockPinOn(int length) {
    return 'Вкл., цифр: $length';
  }

  @override
  String get settingsLockPinOff => 'Выкл.';

  @override
  String get settingsLockPinSetUp => 'Задать PIN-код';

  @override
  String get settingsLockPinChange => 'Изменить PIN-код';

  @override
  String get settingsLockPinRemove => 'Удалить PIN-код';

  @override
  String get settingsLockPinSave => 'Сохранить PIN-код';

  @override
  String get settingsLockPinPassword => 'Пароль учётной записи';

  @override
  String get settingsLockPinNew => 'Новый PIN-код';

  @override
  String get settingsLockPinConfirm => 'Подтвердите PIN-код';

  @override
  String get settingsLockPinLengthHint => 'От 4 до 12 цифр';

  @override
  String get settingsLockPinMismatch => 'PIN-коды не совпадают';

  @override
  String get settingsLockPinWrongPassword => 'Неверный пароль';

  @override
  String get settingsLockPinUnavailable =>
      'Не удалось изменить PIN-код. Повторите попытку.';

  @override
  String timeTwelveHour(String hour, String minute, String period) {
    return '$hour:$minute $period';
  }

  @override
  String get timeMorning => 'AM';

  @override
  String get timeAfternoon => 'PM';

  @override
  String get settingsNavigationPermissions => 'Разрешения';

  @override
  String get settingsPermissionsSection => 'Разрешения';

  @override
  String get settingsPermissionsTitle =>
      'Выберите, что разрешено приложениям. Приложение появится здесь после первого запроса.';

  @override
  String get settingsPermissionsKeyboardShortcutsTitle => 'Сочетания клавиш';

  @override
  String get settingsPermissionsKeyboardShortcutsDescription =>
      'Пока разрешённое приложение в фокусе, оно получает клавиши, которые Denial использует для своих сочетаний, например Super.';

  @override
  String get settingsPermissionsNone =>
      'Пока ни одно приложение не запрашивало.';

  @override
  String get settingsPermissionsUnavailable =>
      'Не удалось прочитать разрешения: хранилище разрешений портала недоступно.';

  @override
  String get settingsPermissionsSaveFailed => 'Не удалось сохранить изменение.';

  @override
  String get settingsPermissionAsk => 'Спрашивать';

  @override
  String get settingsPermissionAllow => 'Разрешать всегда';

  @override
  String get settingsPermissionDeny => 'Никогда не разрешать';

  @override
  String get colorTuningAction => 'Настроить цвета';

  @override
  String get colorTuningDesktop => 'Рабочий стол';

  @override
  String get colorTuningNoApp => 'Коснитесь окна';

  @override
  String get colorTuningBase => 'Стиль';

  @override
  String get colorTuningNoBase => 'Нет';

  @override
  String get colorTuningBefore => 'До';

  @override
  String get colorTuningReset => 'Сбросить';

  @override
  String get colorTuningClose => 'Закрыть';

  @override
  String get colorTuningShadows => 'Тени';

  @override
  String get colorTuningMidtones => 'Средние тона';

  @override
  String get colorTuningHighlights => 'Света';

  @override
  String get colorTuningExposure => 'Экспозиция';

  @override
  String get colorTuningContrast => 'Контраст';

  @override
  String get colorTuningSaturation => 'Насыщенность';

  @override
  String get colorTuningVibrance => 'Сочность';

  @override
  String get colorTuningWarmth => 'Теплота';

  @override
  String get colorTuningTint => 'Оттенок';

  @override
  String get colorTuningFailed => 'Не удалось изменить цвета.';

  @override
  String get colorPresetWarm => 'Тёплый';

  @override
  String get colorPresetCool => 'Холодный';

  @override
  String get colorPresetLogix => 'Logix';

  @override
  String get colorPresetMatte => 'Матовый';

  @override
  String get colorPresetFilm => 'Плёнка';

  @override
  String get colorPresetNight => 'Ночь';

  @override
  String get colorPresetMono => 'Моно';

  @override
  String get colorTuningPresets => 'Пресеты';

  @override
  String get moveToMonitor => 'Перенести на монитор';

  @override
  String get setupWelcome => 'Добро пожаловать';

  @override
  String get setupLanguageBody => 'Выберите язык.';

  @override
  String get setupWifiTitle => 'Wi-Fi';

  @override
  String get setupWifiBody => 'Подключитесь сейчас или позже — из шторки.';

  @override
  String get setupTimeZoneTitle => 'Часовой пояс';

  @override
  String get setupTimeZoneSearch => 'Поиск города';

  @override
  String get setupPersonTitle => 'О вас';

  @override
  String get setupName => 'Ваше имя';

  @override
  String get setupUsername => 'Имя пользователя';

  @override
  String get setupUsernameRules =>
      'Строчные латинские буквы, цифры, - и _; первой должна быть буква.';

  @override
  String get setupNameRules => 'Введите имя без двоеточия.';

  @override
  String get setupPasswordTitle => 'Пароль';

  @override
  String get setupPasswordBody =>
      'Он разблокирует устройство и разрешает изменения в системе.';

  @override
  String get setupPassword => 'Пароль';

  @override
  String get setupPasswordAgain => 'Пароль ещё раз';

  @override
  String get setupPasswordMismatch => 'Пароли не совпадают.';

  @override
  String get setupPinTitle => 'PIN-код блокировки';

  @override
  String get setupPinBody =>
      'Шесть цифр разблокируют устройство быстрее пароля. Пропустите, чтобы добавить PIN-код позже в настройках.';

  @override
  String get setupPin => 'Придумайте шесть цифр';

  @override
  String get setupPinAgain => 'Введите их ещё раз';

  @override
  String get setupPinNotSet =>
      'Учётная запись готова, но PIN-код не задан. Добавьте его в настройках.';

  @override
  String get setupPinMismatch => 'PIN-коды не совпадают.';

  @override
  String get setupFingerprintTitle => 'Отпечаток пальца';

  @override
  String get setupFingerprintBody =>
      'Разблокировка касанием сканера. Пропустите, чтобы добавить отпечаток позже в настройках.';

  @override
  String get setupFingerprintAdd => 'Добавить отпечаток';

  @override
  String get setupFingerprintHold =>
      'Держите палец на круге, пока кольцо не сдвинется, затем поднимите его.';

  @override
  String get setupDeviceTitle => 'Имя устройства';

  @override
  String get setupDeviceBody =>
      'Это имя видят другие устройства по Wi-Fi, Bluetooth и USB.';

  @override
  String get setupBack => 'Назад';

  @override
  String get setupNext => 'Далее';

  @override
  String get setupSkip => 'Пропустить';

  @override
  String get setupFinish => 'Готово';

  @override
  String get setupStarting => 'Запуск…';

  @override
  String get setupNotAllowed =>
      'Программе настройки не разрешено создавать здесь учётную запись.';

  @override
  String setupStartFailed(String reason) {
    return 'Не удалось запустить устройство под вашей учётной записью: $reason';
  }

  @override
  String setupFailed(String reason) {
    return 'Учётная запись не создана: $reason';
  }

  @override
  String get userVerificationTitle => 'Подтвердите, что это вы';

  @override
  String userVerificationAsksPin(String applicationName) {
    return '$applicationName запрашивает PIN-код';
  }

  @override
  String userVerificationAsksPassword(String applicationName) {
    return '$applicationName запрашивает пароль';
  }

  @override
  String get userVerificationWrongPassword => 'Неверный пароль';

  @override
  String get userVerificationConfirm => 'Подтвердить';

  @override
  String get lockEditorHint =>
      'Перетащите часы, чтобы переместить их; сведите или разведите пальцы, чтобы изменить размер';

  @override
  String get lockEditorSwapSides => 'Поменять стороны';

  @override
  String get lockEditorReset => 'Сбросить';

  @override
  String get lockEditorCancel => 'Отмена';

  @override
  String get lockEditorDone => 'Готово';

  @override
  String get lockEditorPinPad => 'Панель PIN-кода';

  @override
  String get lockEditorNotifications => 'Уведомления';

  @override
  String get lockEditorPortrait =>
      'Поверните планшет горизонтально, чтобы настроить экран блокировки';

  @override
  String get mobilePowerTapToRestart => 'Нажмите ещё раз для перезагрузки';

  @override
  String get mobilePowerTapToPowerOff => 'Нажмите ещё раз для выключения';

  @override
  String get mobilePowerMenuSemantics => 'Меню питания';

  @override
  String get homeEditorAddPage => 'Добавить страницу';

  @override
  String get homeEditorRemovePage => 'Удалить страницу';

  @override
  String get homeEditorDrawer => 'Меню приложений';

  @override
  String get homeEditorDrawerDetail =>
      'Проведите вверх по главному экрану, чтобы увидеть все приложения';

  @override
  String get homeEditorSharedRow => 'Закреплённый нижний ряд';

  @override
  String get homeEditorSharedRowDetail =>
      'Нижний ряд остаётся на месте при смене страницы';

  @override
  String get homeEditorDone => 'Готово';

  @override
  String get homeDrawerSemantics => 'Все приложения';

  @override
  String get powerActionRestartDenial => 'Перезапустить Denial';

  @override
  String get powerActionRestartDenialDescription =>
      'Запустить Denial заново; открытые приложения закроются';

  @override
  String get powerConfirmRestartDenialTitle => 'Перезапустить Denial?';

  @override
  String get powerConfirmRestartDenialBody =>
      'Открытые приложения закроются, и Denial запустится заново.';

  @override
  String get mobilePowerTapToRestartDenial =>
      'Нажмите ещё раз, чтобы перезапустить Denial. Открытые приложения закроются.';

  @override
  String get weekdayShortMonday => 'Пн';

  @override
  String get weekdayShortTuesday => 'Вт';

  @override
  String get weekdayShortWednesday => 'Ср';

  @override
  String get weekdayShortThursday => 'Чт';

  @override
  String get weekdayShortFriday => 'Пт';

  @override
  String get weekdayShortSaturday => 'Сб';

  @override
  String get weekdayShortSunday => 'Вс';

  @override
  String get monthShortJanuary => 'янв.';

  @override
  String get monthShortFebruary => 'февр.';

  @override
  String get monthShortMarch => 'мар.';

  @override
  String get monthShortApril => 'апр.';

  @override
  String get monthShortMay => 'мая';

  @override
  String get monthShortJune => 'июн.';

  @override
  String get monthShortJuly => 'июл.';

  @override
  String get monthShortAugust => 'авг.';

  @override
  String get monthShortSeptember => 'сент.';

  @override
  String get monthShortOctober => 'окт.';

  @override
  String get monthShortNovember => 'нояб.';

  @override
  String get monthShortDecember => 'дек.';
}
