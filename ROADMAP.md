# Roadmap

Tracks two kinds of ideas for future development: planned features actually committed to a future release, and proposed features that are just collected ideas, not actively planned or prioritized.

## Planned Features

Nothing planned right now. All previously planned features have shipped.

## Proposed Features

1. **Transition Styles**: choose how one photo gives way to the next with a setting such as `SLIDESHOW_TRANSITION`, for example `crossfade` (today's behavior and the default), `slide`, `zoom`, `none` for a hard cut, or `random` to pick one per photo. The page switches photos by moving an `active` class between two stacked images, with a 1.5 second CSS opacity transition that `fadeMs` in the page's JavaScript must match, so each style would be its own pair of CSS classes, with `-webkit-transform` and `-webkit-transition` for iOS 9 Safari. Slides and zooms move full-size photos, which may stutter on the iPad 3's A5X, so each style needs testing on the iPad itself. Like the other slideshow settings, the value reaches the page through nginx's `envsubst`, so it needs a default in `15-defaults.envsh` (a blank value breaks the page's JavaScript), plus the usual entries in `compose.yaml`, the README's compose block and its settings table.
