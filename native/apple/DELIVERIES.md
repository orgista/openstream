# Deliveries

## OpenStream iOS TestFlight delivery — 4 September 2026
**OpenStream 1.0 (6) is available to Anthony in TestFlight.** Apple processed the upload successfully and reports `VALID` and `IN_BETA_TESTING`. The existing Internal group includes Anthony and automatically receives all builds; build 6 is explicitly present in that group. Installation of this particular build on Anthony’s device has not been observed.

## OpenStream iOS TestFlight delivery — September 10, 2026
**OpenStream 1.0 (7) is available to Anthony in TestFlight.** Apple completed processing and reports `VALID` and `IN_BETA_TESTING`. Build 7 is present in the existing Internal group, which still includes Anthony. Installation of build 7 on his phone has not been observed; build 6 was installed when checked during this review.

## OpenStream iOS TestFlight delivery — September 11, 2026 (build 9)
**OpenStream 1.0 (9) is available to Anthony in TestFlight.** Apple processing `VALID`; internal state `IN_BETA_TESTING`; present in the existing Internal group (`ca5595ab-44fd-4063-bb55-89a053bf2736`) alongside builds 7 and 8. Build ID `5aad4dbc-0515-4d48-a397-c0c22033dc24`. What to Test notes set and read back (en-US localization `03538f2f-6d70-45be-880d-b5121d8b6e96`).

Export rule: use the App Store profile with Group Activities (`75afc0e9-11e3-4236-b7e4-95c4b8d7bc79`, ExportOptions-Manual.plist in artifacts/testflight/2026-09-10/shareplay-build-8-final); `manageAppVersionAndBuildNumber` assigns the next build number. Signing identity lives in `~/Developer/openstream-build/openstream.keychain-db`.
