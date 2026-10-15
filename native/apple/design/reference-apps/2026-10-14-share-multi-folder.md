# Infuse: several folders from one share

Static artifact check, 2026-10-14. Target: the approved Infuse 8.5.6 copy on Dev-Mini. The target was not launched, no share or account was contacted, and no code or assets were copied.

## Evidence

`/Volumes/DevExt/dev/rea/targets/Infuse.app/Contents/Resources/en.lproj/Localizable.strings`, decoded as UTF-16:

- Line 1402, `tvshAddFavorite`: the action supports adding favorites in the plural.
- Line 1404, `tvshSavedShareHint`: describes choosing favorite folders after a share has been saved.
- Lines 478 and 500 identify library/home favorite actions.

The existing `2026-10-11-infuse-engine-sources.md` report documents separate saved-share, connection and folder-browser components. These resources support a saved connection with multiple chosen folders. They do not establish exact tap behavior, focus movement, defaults or credential lifetime; no runtime claims are made.

## OpenStream policy

Keep one existing `.nas` source per selected folder, with no snapshot fields or migration. Keep selection in the setup object while navigating. Give folder navigation and selection separate controls, reject overlapping roots, and confirm editable names together. Group saved folders by server and share, with Add Folder using a saved account. Share one credential reference for the same server/account and keep it while any source uses it.

The exact controls, overlap policy and credential sharing follow the owner's decisions in `specs/share-multi-folder-2026-10-13.md`. Runtime comparison remains unverified.
