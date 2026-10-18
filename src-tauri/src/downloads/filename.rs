use crate::media::Quality;

pub(super) const MAX_STEM_UNITS: usize = 150;
const MAX_STEM_BYTES: usize = 220;

pub(super) fn portable_stem(value: &str, units: usize) -> String {
    let mut result = String::new();
    let mut used = 0;
    for character in value.chars() {
        let character = if character.is_control() || "<>:\"/\\|?*".contains(character) {
            '_'
        } else {
            character
        };
        if used + character.len_utf16() > units
            || result.len() + character.len_utf8() > MAX_STEM_BYTES
        {
            break;
        }
        used += character.len_utf16();
        result.push(character);
    }

    let mut result = result.trim_end_matches(['.', ' ']).to_owned();
    if result.is_empty() {
        result.push_str("video");
    }

    let device = result
        .split('.')
        .next()
        .unwrap()
        .trim_end()
        .to_ascii_uppercase();
    if ["CON", "PRN", "AUX", "NUL"].contains(&device.as_str())
        || device
            .strip_prefix("COM")
            .or_else(|| device.strip_prefix("LPT"))
            .is_some_and(|suffix| {
                ["1", "2", "3", "4", "5", "6", "7", "8", "9", "¹", "²", "³"].contains(&suffix)
            })
    {
        result.insert(0, '_');
    }

    result
}

pub fn download_filename(date: &str, title: &str, quality: Quality) -> String {
    let quality = if quality == Quality::Standard {
        "标准"
    } else {
        "流畅"
    };
    format!(
        "{}.mp4",
        portable_stem(&format!("{date}_{title}_{quality}"), MAX_STEM_UNITS)
    )
}
