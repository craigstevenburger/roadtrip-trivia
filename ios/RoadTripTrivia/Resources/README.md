# Resources

Drop your `GoogleService-Info.plist` (downloaded from the Firebase console
for the iOS app you register there) into this folder before building.
`xcodegen generate` picks up everything under `RoadTripTrivia/` as either
source or resource automatically, so no project.yml changes are needed —
just add the file and regenerate.

This file is a placeholder so the empty `Resources/` folder is tracked by
git; delete this note once `GoogleService-Info.plist` is in place.
