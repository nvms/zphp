// timelib's astro.c (php's ext/date/lib): sunrise, sunset and twilight from
// Paul Schlyter's public domain algorithms, for date_sun_info(),
// date_sunrise() and date_sunset()
const std = @import("std");

// libm's, as timelib calls them: zig's own differ from glibc's in the last
// bits, which shows in date_sunrise()'s float results
extern "c" fn sin(x: f64) f64;
extern "c" fn cos(x: f64) f64;
extern "c" fn acos(x: f64) f64;
extern "c" fn atan2(y: f64, x: f64) f64;
extern "c" fn sqrt(x: f64) f64;

const radeg = 180.0 / std.math.pi;
const degrad = std.math.pi / 180.0;
const inv360 = 1.0 / 360.0;

fn sind(x: f64) f64 {
    return sin(x * degrad);
}

fn cosd(x: f64) f64 {
    return cos(x * degrad);
}

fn atan2d(y: f64, x: f64) f64 {
    return radeg * atan2(y, x);
}

fn acosd(x: f64) f64 {
    return radeg * acos(x);
}

fn revolution(x: f64) f64 {
    return x - 360.0 * @floor(x * inv360);
}

fn rev180(x: f64) f64 {
    return x - 360.0 * @floor(x * inv360 + 0.5);
}

fn gmst0(d: f64) f64 {
    return revolution((180.0 + 356.0470 + 282.9404) + (0.9856002585 + 4.70935E-5) * d);
}

fn sunpos(d: f64, lon: *f64, r: *f64) void {
    const m = revolution(356.0470 + 0.9856002585 * d);
    const w = 282.9404 + 4.70935E-5 * d;
    const e = 0.016709 - 1.151E-9 * d;
    const ecc = m + e * radeg * sind(m) * (1.0 + e * cosd(m));
    const x = cosd(ecc) - e;
    const y = sqrt(1.0 - e * e) * sind(ecc);
    r.* = sqrt(x * x + y * y);
    const v = atan2d(y, x);
    lon.* = v + w;
    if (lon.* >= 360.0) lon.* -= 360.0;
}

fn sunRaDec(d: f64, ra: *f64, dec: *f64, r: *f64) void {
    var lon: f64 = 0;
    sunpos(d, &lon, r);
    const x = r.* * cosd(lon);
    var y = r.* * sind(lon);
    const obl_ecl = 23.4393 - 3.563E-7 * d;
    const z = y * sind(obl_ecl);
    y = y * cosd(obl_ecl);
    ra.* = atan2d(y, x);
    dec.* = atan2d(z, sqrt(x * x + y * y));
}

// c's conversion of a double to an integer: toward zero, and an
// out-of-range value saturated rather than undefined
fn toLong(v: f64) i64 {
    if (std.math.isNan(v)) return std.math.minInt(i64);
    if (v >= 9223372036854775807.0) return std.math.maxInt(i64);
    if (v <= -9223372036854775808.0) return std.math.minInt(i64);
    return @intFromFloat(@trunc(v));
}

pub const RiseSet = struct {
    // -1 always below the altitude, 1 always above, 0 rises and sets
    rc: i32,
    h_rise: ?f64 = null,
    h_set: ?f64 = null,
    rise: i64,
    set: i64,
    transit: i64,
};

// timelib_astro_rise_set_altitude. noon_sse is the local noon of the day
// (t_loc after its fields are set to 12:00:00 and resolved), utc_midnight
// the utc midnight of the local date
pub fn riseSetAltitude(noon_sse: i64, utc_midnight: i64, lon: f64, lat: f64, altit_in: f64, upper_limb: bool) RiseSet {
    var altit = altit_in;
    const midnight: f64 = @floatFromInt(utc_midnight);
    const d = (midnight / 86400.0 + 2440587.5 - 2451545.0) + 2 - lon / 360.0;
    const sidtime = revolution(gmst0(d) + 180.0 + lon);
    var sra: f64 = 0;
    var sdec: f64 = 0;
    var sr: f64 = 0;
    sunRaDec(d, &sra, &sdec, &sr);
    const tsouth = 12.0 - rev180(sidtime - sra) / 15.0;
    const sradius = 0.2666 / sr;
    if (upper_limb) altit -= sradius;
    const cost = (sind(altit) - sind(lat) * sind(sdec)) / (cosd(lat) * cosd(sdec));
    var out = RiseSet{ .rc = 0, .rise = 0, .set = 0, .transit = toLong(midnight + tsouth * 3600) };
    if (cost >= 1.0) {
        out.rc = -1;
        out.rise = toLong(midnight + tsouth * 3600);
        out.set = out.rise;
    } else if (cost <= -1.0) {
        out.rc = 1;
        out.rise = noon_sse - 12 * 3600;
        out.set = noon_sse + 12 * 3600;
    } else {
        const t = acosd(cost) / 15.0;
        out.rise = toLong((tsouth - t) * 3600 + midnight);
        out.set = toLong((tsouth + t) * 3600 + midnight);
        out.h_rise = tsouth - t;
        out.h_set = tsouth + t;
    }
    return out;
}
