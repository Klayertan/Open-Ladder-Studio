# Open Ladder Studio delivery

After making application changes, build and run the relevant checks, then run
`python3 Scripts/package_dmg.py` to package the updated macOS app. The packaging
script builds the app, verifies its signature, creates and verifies a DMG, and
copies it into the user's Downloads folder. Include a clickable absolute link to
the new DMG in the final response. This delivery preference applies to every
future application update in this repository.
