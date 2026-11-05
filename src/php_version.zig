// the php release zphp reports itself as. zphp tracks the latest stable php,
// so bump this when the compat suite moves to a new release
pub const major = 8;
pub const minor = 5;
pub const release = 12;

pub const string = std.fmt.comptimePrint("{d}.{d}.{d}", .{ major, minor, release });
pub const id = major * 10000 + minor * 100 + release;

// PHP_BUILD_DATE, in php's `__DATE__ __TIME__` form ("Sep  2 2026 14:42:18"),
// for the build's source date (see buildEpoch in build.zig)
pub const build_date = formatBuildDate(@import("build_role").build_epoch);

fn formatBuildDate(comptime epoch: i64) []const u8 {
    @setEvalBranchQuota(100_000);
    const secs = std.time.epoch.EpochSeconds{ .secs = @intCast(@max(epoch, 0)) };
    const year_day = secs.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_secs = secs.getDaySeconds();
    const months = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
    return std.fmt.comptimePrint("{s} {d: >2} {d} {d:0>2}:{d:0>2}:{d:0>2}", .{
        months[month_day.month.numeric() - 1],
        month_day.day_index + 1,
        year_day.year,
        day_secs.getHoursIntoDay(),
        day_secs.getMinutesIntoHour(),
        day_secs.getSecondsIntoMinute(),
    });
}

const std = @import("std");
