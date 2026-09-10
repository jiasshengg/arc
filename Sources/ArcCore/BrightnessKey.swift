/// Decode only brightness key-down events, including hardware key repeats.
/// No typed characters or general keyboard events are collected.
public enum BrightnessKey {
    public static func isAdjustment(subtype: Int16, data: Int) -> Bool {
        guard subtype == 8 else { return false }
        let key = (data >> 16) & 0xffff
        let state = (data >> 8) & 0xff
        return (key == 2 || key == 3) && state == 0x0a
    }
}
