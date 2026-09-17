class_name GodotSkillImageDescribe
extends RefCounted

# Turns an Image into numbers and ASCII so a caller that cannot look at pixels
# can still verify what was drawn: is anything there, where is it, how big is
# the palette, did it change since the last capture.
#
# Pure by design — it never logs, never touches the filesystem and never needs a
# rendering device, so it runs under `--headless` (dummy renderer) and can be
# called from an op (inspect_image.gd) or from the scenario runner's screenshot
# step. Callers own the IO and the error reporting.
#
# Cost control: the colour statistics (opaque_ratio, mean_color,
# dominant_colors, unique_colors, quadrants, diff_ratio) are measured on a
# nearest-neighbour downscale capped at SAMPLE_MAX_SIDE px on the long side, so
# a 1920x1080 screenshot costs the same as a 256x144 one. Nearest-neighbour is
# deliberate: it invents no blended colours, so a pixel-art palette stays
# countable. width/height/has_alpha/blank/content_bbox are measured on the FULL
# image — the bbox is the number callers position things by, so it is never an
# estimate. A 1080p capture describes in well under a second.

const RAMP = " .:-=+*#%@"
const SAMPLE_MAX_SIDE = 256
const DEFAULT_ASCII_WIDTH = 64
const MIN_ASCII_WIDTH = 4
const MAX_ASCII_WIDTH = 240
# A very tall image would otherwise turn one ascii_width into thousands of rows;
# columns shrink instead, so the drawing keeps its aspect ratio.
const MAX_ASCII_ROWS = 240
const DEFAULT_MAX_UNIQUE = 4096
const DOMINANT_COLOR_COUNT = 8
# "changed" is a channel delta above 8/255, so 8-bit rounding and lossy-codec
# noise do not read as a difference.
const DIFF_CHANNEL_EPSILON = 8.0 / 255.0
# Lossy codecs (JPEG, lossy WebP) ring around every edge with near-background
# pixels. "background_tolerance" is the per-channel delta (0..1) under which a
# pixel still counts as background for content_bbox and the quadrant shares;
# 0 keeps the exact match that lossless art wants.
const DEFAULT_BACKGROUND_TOLERANCE = 0.0
# Per-axis sample cap inside one ASCII cell: a cell always averages at most
# 8x8 probes, so ascii cost does not grow with image size.
const ASCII_CELL_SAMPLES = 8
const ASCII_MIN_COVERAGE = 0.05
const ASCII_FLAT_SPAN = 0.02
const COLOR_LETTERS = "KWRGBYCM"
const COLOR_LETTER_RGB = [[0, 0, 0], [1, 1, 1], [1, 0, 0], [0, 1, 0], [0, 0, 1], [1, 1, 0], [0, 1, 1], [1, 0, 1]]


static func describe(image: Image, options: Dictionary) -> Dictionary:
    if image == null:
        return {"error": "describe() needs an Image; got null (load one with Image.load_from_file first)"}

    var work := _to_rgba8(image)
    if work == null:
        return {"error": "image is VRAM-compressed and could not be decompressed; reimport the texture as lossless (Import > Compress > Mode: Lossless)"}
    var width := work.get_width()
    var height := work.get_height()
    if width <= 0 or height <= 0:
        return {"error": "image is empty (0x0); re-export the file"}

    var background := _background_color(work)
    var tolerance := clampf(float(options.get("background_tolerance", DEFAULT_BACKGROUND_TOLERANCE)), 0.0, 1.0)
    var used_rect := work.get_used_rect()
    var sample := _sample_image(work)
    var stats := _color_stats(sample, background, tolerance, maxi(1, int(options.get("max_unique", DEFAULT_MAX_UNIQUE))))

    var result := {}
    result["width"] = width
    result["height"] = height
    result["has_alpha"] = work.detect_alpha() != Image.ALPHA_NONE
    result["blank"] = _is_blank(work, used_rect)
    result["opaque_ratio"] = stats["opaque_ratio"]
    var bbox := _content_bbox(work, background, tolerance, used_rect)
    if bbox.size.x > 0 and bbox.size.y > 0:
        result["content_bbox"] = {"x": bbox.position.x, "y": bbox.position.y, "w": bbox.size.x, "h": bbox.size.y}
        result["content_bbox_normalized"] = {
            "x": float(bbox.position.x) / float(width),
            "y": float(bbox.position.y) / float(height),
            "w": float(bbox.size.x) / float(width),
            "h": float(bbox.size.y) / float(height)
        }
    else:
        result["content_bbox"] = null
        result["content_bbox_normalized"] = null
    result["mean_color"] = stats["mean_color"]
    result["dominant_colors"] = stats["dominant_colors"]
    result["unique_colors"] = stats["unique_colors"]
    result["quadrants"] = stats["quadrants"]
    result["background_color"] = "#" + background.to_html(false)
    result["background_transparent"] = background.a <= 0.0
    result["background_tolerance"] = tolerance
    result["sample_size"] = {"width": sample.get_width(), "height": sample.get_height()}
    result["sampled"] = sample.get_width() != width or sample.get_height() != height

    var want_ascii := bool(options.get("ascii", false))
    var want_ascii_color := bool(options.get("ascii_color", false))
    if want_ascii or want_ascii_color:
        var columns := clampi(int(options.get("ascii_width", DEFAULT_ASCII_WIDTH)), MIN_ASCII_WIDTH, MAX_ASCII_WIDTH)
        var art := _ascii_render(work, columns)
        if want_ascii:
            result["ascii"] = art["ascii"]
        if want_ascii_color:
            result["ascii_color"] = art["ascii_color"]

    var compare_value: Variant = options.get("compare_to", null)
    if compare_value is Image:
        var other := _to_rgba8(compare_value as Image)
        if other == null:
            result["diff_error"] = "compare_to is VRAM-compressed and could not be decompressed; reimport it as lossless"
        elif other.get_width() != width or other.get_height() != height:
            result["diff_error"] = "compare_to is %dx%d but this image is %dx%d - compare captures of the same size (re-capture with the same viewport_size, or resize one first)" % [other.get_width(), other.get_height(), width, height]
        else:
            result["diff_ratio"] = _diff_ratio(work, other)
    return result


static func _to_rgba8(source: Image) -> Image:
    # Every read below assumes straight RGBA8: a VRAM-compressed or L8/RGB8
    # texture answers get_pixel() differently (or not at all), so normalise once.
    var copy := Image.new()
    copy.copy_from(source)
    if copy.is_compressed() and copy.decompress() != OK:
        return null
    if copy.get_format() != Image.FORMAT_RGBA8:
        copy.convert(Image.FORMAT_RGBA8)
    return copy


static func _sample_image(image: Image) -> Image:
    var long_side := maxi(image.get_width(), image.get_height())
    if long_side <= SAMPLE_MAX_SIDE:
        return image
    var scale := float(SAMPLE_MAX_SIDE) / float(long_side)
    var copy := Image.new()
    copy.copy_from(image)
    copy.resize(
        maxi(1, int(round(image.get_width() * scale))),
        maxi(1, int(round(image.get_height() * scale))),
        Image.INTERPOLATE_NEAREST
    )
    return copy


static func _background_color(image: Image) -> Color:
    # The background is whatever the four corners agree on; ties go to the
    # top-left corner so the answer is stable across runs. A fully transparent
    # corner is normalised so transparent pixels compare equal whatever RGB the
    # exporter left behind them.
    var width := image.get_width()
    var height := image.get_height()
    var corners: Array[Color] = [
        image.get_pixel(0, 0),
        image.get_pixel(width - 1, 0),
        image.get_pixel(0, height - 1),
        image.get_pixel(width - 1, height - 1)
    ]
    var counts := {}
    var best := corners[0]
    var best_count := 0
    for corner in corners:
        var color := Color(0, 0, 0, 0) if corner.a <= 0.0 else corner
        var key := int(color.to_rgba32())
        var seen := int(counts.get(key, 0)) + 1
        counts[key] = seen
        if seen > best_count:
            best_count = seen
            best = color
    return best


static func _is_blank(image: Image, used_rect: Rect2i) -> bool:
    if used_rect.size.x <= 0 or used_rect.size.y <= 0:
        return true
    # One native memcmp against a solid fill of the first pixel: exact over every
    # channel, and far cheaper than a per-pixel loop.
    var flat := Image.create_empty(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
    flat.fill(image.get_pixel(0, 0))
    return image.get_data() == flat.get_data()


static func _matches_background(color: Color, background: Color, tolerance: float) -> bool:
    if tolerance <= 0.0:
        return int(color.to_rgba32()) == int(background.to_rgba32())
    if background.a <= 0.0:
        return color.a <= 0.0
    var delta := maxf(
        maxf(absf(color.r - background.r), absf(color.g - background.g)),
        maxf(absf(color.b - background.b), absf(color.a - background.a))
    )
    return delta <= tolerance


static func _content_bbox(image: Image, background: Color, tolerance: float, used_rect: Rect2i) -> Rect2i:
    # Full-image scan: content is every pixel that is neither transparent nor the
    # background colour. Once a row's x-range is known the scan jumps over the
    # span already inside the box, so a full-frame screenshot costs a couple of
    # reads per row and an all-background image is the only worst case.
    if used_rect.size.x <= 0 or used_rect.size.y <= 0:
        return Rect2i(0, 0, 0, 0)
    var width := image.get_width()
    var height := image.get_height()
    var min_x := width
    var min_y := height
    var max_x := -1
    var max_y := -1
    for y in range(height):
        var row_hit := false
        var x := 0
        while x < width:
            var color := image.get_pixel(x, y)
            if color.a > 0.0 and not _matches_background(color, background, tolerance):
                if not row_hit:
                    row_hit = true
                    min_y = mini(min_y, y)
                    max_y = y
                var jump := x < max_x
                min_x = mini(min_x, x)
                max_x = maxi(max_x, x)
                if jump:
                    x = max_x
            x += 1
    if max_x < 0:
        return Rect2i(0, 0, 0, 0)
    var box := Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
    # A fully transparent pixel is background even when the corners are opaque,
    # so clip the box to the region that actually has alpha.
    return box.intersection(used_rect)


static func _color_stats(sample: Image, background: Color, tolerance: float, max_unique: int) -> Dictionary:
    var width := sample.get_width()
    var height := sample.get_height()
    var total := width * height
    var visible := 0
    var sum_r := 0.0
    var sum_g := 0.0
    var sum_b := 0.0
    var quantised := {}
    var exact := {}
    var unique_overflow := false
    var quadrant_counts := [0, 0, 0, 0]
    var content := 0

    for y in range(height):
        for x in range(width):
            var color := sample.get_pixel(x, y)
            if color.a <= 0.0:
                continue
            visible += 1
            sum_r += color.r
            sum_g += color.g
            sum_b += color.b
            var bucket := ((color.r8 >> 4) << 8) | ((color.g8 >> 4) << 4) | (color.b8 >> 4)
            quantised[bucket] = int(quantised.get(bucket, 0)) + 1
            if not unique_overflow:
                exact[int(color.to_rgba32())] = true
                if exact.size() > max_unique:
                    unique_overflow = true
            if _matches_background(color, background, tolerance):
                continue
            content += 1
            var index := (0 if y * 2 < height else 2) + (0 if x * 2 < width else 1)
            quadrant_counts[index] = int(quadrant_counts[index]) + 1

    var mean := Color(0, 0, 0, 1)
    if visible > 0:
        mean = Color(sum_r / visible, sum_g / visible, sum_b / visible, 1.0)

    var buckets: Array = []
    for key in quantised.keys():
        buckets.append({"key": int(key), "count": int(quantised[key])})
    buckets.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
        if int(left["count"]) != int(right["count"]):
            return int(left["count"]) > int(right["count"])
        return int(left["key"]) < int(right["key"])
    )
    var dominant: Array = []
    for entry in buckets.slice(0, DOMINANT_COLOR_COUNT):
        var key := int(entry["key"])
        var red := (key >> 8) & 0xF
        var green := (key >> 4) & 0xF
        var blue := key & 0xF
        dominant.append({
            "hex": "#%02x%02x%02x" % [(red << 4) | red, (green << 4) | green, (blue << 4) | blue],
            "ratio": float(int(entry["count"])) / float(maxi(visible, 1))
        })

    var quadrant_total := float(maxi(content, 1))
    return {
        "opaque_ratio": float(visible) / float(maxi(total, 1)),
        "mean_color": "#" + mean.to_html(false),
        "dominant_colors": dominant,
        "unique_colors": max_unique if unique_overflow else exact.size(),
        "quadrants": {
            "top_left": float(int(quadrant_counts[0])) / quadrant_total,
            "top_right": float(int(quadrant_counts[1])) / quadrant_total,
            "bottom_left": float(int(quadrant_counts[2])) / quadrant_total,
            "bottom_right": float(int(quadrant_counts[3])) / quadrant_total
        }
    }


static func _ascii_render(image: Image, columns: int) -> Dictionary:
    # Character cells are about twice as tall as they are wide, so halve the row
    # count or every drawing comes out stretched.
    var width := image.get_width()
    var height := image.get_height()
    var rows := maxi(1, int(round(float(height) * float(columns) / float(width) / 2.0)))
    if rows > MAX_ASCII_ROWS:
        columns = maxi(MIN_ASCII_WIDTH, int(float(columns) * float(MAX_ASCII_ROWS) / float(rows)))
        rows = maxi(1, int(round(float(height) * float(columns) / float(width) / 2.0)))
    var values := PackedFloat32Array()
    var coverage := PackedFloat32Array()
    var colors := PackedColorArray()
    var lowest := 1.0
    var highest := 0.0
    var has_gap := false

    for row in range(rows):
        var y0 := int(float(row) * height / rows)
        var y1 := maxi(y0 + 1, int(float(row + 1) * height / rows))
        for column in range(columns):
            var x0 := int(float(column) * width / columns)
            var x1 := maxi(x0 + 1, int(float(column + 1) * width / columns))
            var step_x := maxi(1, floori(float(x1 - x0) / ASCII_CELL_SAMPLES))
            var step_y := maxi(1, floori(float(y1 - y0) / ASCII_CELL_SAMPLES))
            var samples := 0
            var alpha_sum := 0.0
            var red_sum := 0.0
            var green_sum := 0.0
            var blue_sum := 0.0
            var y := y0
            while y < y1:
                var x := x0
                while x < x1:
                    var color := image.get_pixel(x, y)
                    alpha_sum += color.a
                    red_sum += color.r * color.a
                    green_sum += color.g * color.a
                    blue_sum += color.b * color.a
                    samples += 1
                    x += step_x
                y += step_y
            var cell_coverage := alpha_sum / float(maxi(samples, 1))
            # Luminance of the cell composited over black, so a half-covered cell
            # reads lighter than a solid one and edges shade off naturally.
            var luminance := (0.2126 * red_sum + 0.7152 * green_sum + 0.0722 * blue_sum) / float(maxi(samples, 1))
            coverage.append(cell_coverage)
            values.append(luminance)
            if alpha_sum > 0.0:
                colors.append(Color(red_sum / alpha_sum, green_sum / alpha_sum, blue_sum / alpha_sum, cell_coverage))
            else:
                colors.append(Color(0, 0, 0, 0))
            if cell_coverage < ASCII_MIN_COVERAGE:
                has_gap = true
            else:
                lowest = minf(lowest, luminance)
                highest = maxf(highest, luminance)

    # The ramp is stretched across the luminance actually present, so a dark
    # scene still shows its shapes instead of collapsing into one character.
    var span := highest - lowest
    var last := RAMP.length() - 1
    var ascii_rows: Array = []
    var color_rows: Array = []
    for row in range(rows):
        var line := ""
        var color_line := ""
        for column in range(columns):
            var index := row * columns + column
            if coverage[index] < ASCII_MIN_COVERAGE:
                line += " "
                color_line += " "
                continue
            var level := 0.0
            if span >= ASCII_FLAT_SPAN:
                level = (values[index] - lowest) / span
            elif has_gap:
                # One flat colour on a transparent background: draw the
                # silhouette solid instead of grading a single shade.
                level = 1.0
            else:
                level = values[index]
            line += RAMP[clampi(int(round(level * last)), 0, last)]
            color_line += _color_letter(colors[index])
        ascii_rows.append(line)
        color_rows.append(color_line)
    return {"ascii": ascii_rows, "ascii_color": color_rows}


static func _color_letter(color: Color) -> String:
    var best := 0
    var best_distance := INF
    for index in range(COLOR_LETTER_RGB.size()):
        var entry: Array = COLOR_LETTER_RGB[index]
        var delta_r := color.r - float(entry[0])
        var delta_g := color.g - float(entry[1])
        var delta_b := color.b - float(entry[2])
        var distance := delta_r * delta_r + delta_g * delta_g + delta_b * delta_b
        if distance < best_distance:
            best_distance = distance
            best = index
    return COLOR_LETTERS[best]


static func _diff_ratio(image: Image, other: Image) -> float:
    # Byte-identical is the assertion that matters most ("nothing changed"), so
    # answer that one exactly and natively before falling back to the sample.
    if image.get_data() == other.get_data():
        return 0.0
    var left := _sample_image(image)
    var right := _sample_image(other)
    var width := mini(left.get_width(), right.get_width())
    var height := mini(left.get_height(), right.get_height())
    var differing := 0
    for y in range(height):
        for x in range(width):
            var a := left.get_pixel(x, y)
            var b := right.get_pixel(x, y)
            if absf(a.r - b.r) > DIFF_CHANNEL_EPSILON \
                    or absf(a.g - b.g) > DIFF_CHANNEL_EPSILON \
                    or absf(a.b - b.b) > DIFF_CHANNEL_EPSILON \
                    or absf(a.a - b.a) > DIFF_CHANNEL_EPSILON:
                differing += 1
    return float(differing) / float(maxi(width * height, 1))
