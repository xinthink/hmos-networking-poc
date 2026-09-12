/**
 * Run environment of the NSC verification suite.
 *
 * Every self-test run is stamped with the OS/API level and device type, so the
 * same suite can be replayed on a newer system version and the hilog lines stay
 * self-describing — no need to remember which build produced them.
 *
 *   NSCTEST ENV HarmonyOS 6.1.1(24) api=24 phone (6.1.0.126)
 */
import { deviceInfo } from '@kit.BasicServicesKit';

/** One-line identity of the current device + OS. */
export function envTag(): string {
  return `${deviceInfo.osFullName} api=${deviceInfo.sdkApiVersion} ${deviceInfo.deviceType} (${deviceInfo.displayVersion})`;
}

/** Distribution (ISV) OS version, if the image declares one. */
export function distributionTag(): string {
  return `${deviceInfo.distributionOSVersion} api=${deviceInfo.sdkApiVersion}`;
}
