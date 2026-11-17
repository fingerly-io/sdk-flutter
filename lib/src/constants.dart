/// Names for the fixed string values the Fingerly API returns.
///
/// Each class holds `static const String` members, so a field keeps its plain
/// `String` type and a value a newer server adds still arrives unchanged:
/// compare with `result.suspectLevel == SuspectLevel.high`, or use the members
/// as `case` labels in a `switch` with a default. A member is its value in
/// lowerCamelCase, word by word (`fingerprint_suppressed` is
/// [Signal.fingerprintSuppressed]), the same names as the other Fingerly SDKs.
library;

/// The score as a band, in `IdentifyResult.suspectLevel`.
abstract final class SuspectLevel {
  static const String low = 'low';
  static const String medium = 'medium';
  static const String high = 'high';

  /// Every level, lowest first.
  static const List<String> values = [low, medium, high];
}

/// How sure the server is of a finding, in `IdentifyTrigger.confidence`.
abstract final class Confidence {
  static const String low = 'low';
  static const String medium = 'medium';
  static const String high = 'high';

  /// Every grade, lowest first.
  static const List<String> values = [low, medium, high];
}

/// The server's disposition of a check, in `IdentifyResult.state`.
///
/// [enriched] when it was fully processed, [unavailable] when the network
/// lookup could not run, so it was not scored. [pending] is a server-side event
/// read's "not recorded yet"; an `identify()` answer is never pending.
abstract final class EventState {
  static const String pending = 'pending';
  static const String enriched = 'enriched';
  static const String unavailable = 'unavailable';

  /// Every state.
  static const List<String> values = [pending, enriched, unavailable];
}

/// Every signal group and raw detector the server reports, in
/// `IdentifyTrigger.signal` and `IdentifyTrigger.group`.
///
/// A trigger's `signal` is a raw detector, such as [vpnPublic]; its `group` is
/// the group it is reported under, such as [vpn]. The signals reach an app only
/// when its key's audience receives triggers; the event your backend reads
/// carries them as well.
abstract final class Signal {
  static const String tor = 'tor';
  static const String datacenterProxy = 'datacenter_proxy';
  static const String proxy = 'proxy';
  static const String datacenterIp = 'datacenter_ip';
  static const String residentialProxy = 'residential_proxy';
  static const String residentialProxyLowConfidence =
      'residential_proxy_low_confidence';
  static const String residentialProxyMediumConfidence =
      'residential_proxy_medium_confidence';
  static const String residentialProxyHighConfidence =
      'residential_proxy_high_confidence';
  static const String vpn = 'vpn';
  static const String vpnPublic = 'vpn_public';
  static const String vpnTimezone = 'vpn_timezone';
  static const String vpnRelay = 'vpn_relay';
  static const String vpnMobile = 'vpn_mobile';
  static const String vpnOsMismatch = 'vpn_os_mismatch';
  static const String vpnLowConfidence = 'vpn_low_confidence';
  static const String vpnMediumConfidence = 'vpn_medium_confidence';
  static const String vpnHighConfidence = 'vpn_high_confidence';
  static const String ipBlocklist = 'ip_blocklist';
  static const String ipBlocklistEmailSpam = 'ip_blocklist_email_spam';
  static const String ipBlocklistAttackSource = 'ip_blocklist_attack_source';
  static const String ipReputation = 'ip_reputation';
  static const String ipAbuser = 'ip_abuser';
  static const String networkAnomaly = 'network_anomaly';
  static const String bogonIp = 'bogon_ip';
  static const String anycastIp = 'anycast_ip';
  static const String locationSpoofing = 'location_spoofing';
  static const String geoMismatch = 'geo_mismatch';
  static const String iosSimulator = 'ios_simulator';
  static const String simulator = 'simulator';
  static const String androidEmulator = 'android_emulator';
  static const String emulator = 'emulator';
  static const String virtualMachine = 'virtual_machine';
  static const String jailbrokenDevice = 'jailbroken_device';
  static const String jailbreak = 'jailbreak';
  static const String rootedDevice = 'rooted_device';
  static const String rootApps = 'root_apps';
  static const String playDeviceIntegrityFailed =
      'play_device_integrity_failed';
  static const String clonedApp = 'cloned_app';
  static const String appCloner = 'app_cloner';
  static const String playAppUnrecognized = 'play_app_unrecognized';
  static const String deviceFarm = 'device_farm';
  static const String repeatedReinstall = 'repeated_reinstall';
  static const String deviceActivityHigh = 'device_activity_high';
  static const String deviceActivityVeryHigh = 'device_activity_very_high';
  static const String mitmAttack = 'mitm_attack';
  static const String fridaDetected = 'frida_detected';
  static const String frida = 'frida';
  static const String browserTampering = 'browser_tampering';
  static const String tampering = 'tampering';
  static const String antidetectBrowser = 'antidetect_browser';
  static const String fingerprintSuppressed = 'fingerprint_suppressed';
  static const String developerTools = 'developer_tools';
  static const String remoteControl = 'remote_control';
  static const String bot = 'bot';
  static const String automation = 'automation';
  static const String badBot = 'bad_bot';
  static const String fetchMetadataMissing = 'fetch_metadata_missing';
  static const String webTicketMissing = 'web_ticket_missing';
  static const String webTicketInvalid = 'web_ticket_invalid';
  static const String highActivity = 'high_activity';
  static const String incognitoMode = 'incognito_mode';
  static const String incognito = 'incognito';
  static const String privacySettings = 'privacy_settings';
  static const String embeddedWebView = 'embedded_web_view';
  static const String activeCall = 'active_call';
  static const String attestationMissing = 'attestation_missing';
  static const String attestationFailed = 'attestation_failed';
  static const String attestationDowngrade = 'attestation_downgrade';
  static const String deviceInconsistent = 'device_inconsistent';
  static const String reportIncomplete = 'report_incomplete';
  static const String probeErrors = 'probe_errors';
  static const String customRootCa = 'custom_root_ca';
  static const String secondaryUserProfile = 'secondary_user_profile';

  /// Every signal the server reports today.
  static const List<String> values = [
    tor,
    datacenterProxy,
    proxy,
    datacenterIp,
    residentialProxy,
    residentialProxyLowConfidence,
    residentialProxyMediumConfidence,
    residentialProxyHighConfidence,
    vpn,
    vpnPublic,
    vpnTimezone,
    vpnRelay,
    vpnMobile,
    vpnOsMismatch,
    vpnLowConfidence,
    vpnMediumConfidence,
    vpnHighConfidence,
    ipBlocklist,
    ipBlocklistEmailSpam,
    ipBlocklistAttackSource,
    ipReputation,
    ipAbuser,
    networkAnomaly,
    bogonIp,
    anycastIp,
    locationSpoofing,
    geoMismatch,
    iosSimulator,
    simulator,
    androidEmulator,
    emulator,
    virtualMachine,
    jailbrokenDevice,
    jailbreak,
    rootedDevice,
    rootApps,
    playDeviceIntegrityFailed,
    clonedApp,
    appCloner,
    playAppUnrecognized,
    deviceFarm,
    repeatedReinstall,
    deviceActivityHigh,
    deviceActivityVeryHigh,
    mitmAttack,
    fridaDetected,
    frida,
    browserTampering,
    tampering,
    antidetectBrowser,
    fingerprintSuppressed,
    developerTools,
    remoteControl,
    bot,
    automation,
    badBot,
    fetchMetadataMissing,
    webTicketMissing,
    webTicketInvalid,
    highActivity,
    incognitoMode,
    incognito,
    privacySettings,
    embeddedWebView,
    activeCall,
    attestationMissing,
    attestationFailed,
    attestationDowngrade,
    deviceInconsistent,
    reportIncomplete,
    probeErrors,
    customRootCa,
    secondaryUserProfile,
  ];
}
