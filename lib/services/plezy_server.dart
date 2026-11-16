import '../utils/build_identity.dart';

/// Base URL of the Plezy server: the tracker OAuth proxy (`/auth`), log
/// uploads (`/logs`) and Discord posters (`/posters`). Watch Together rooms
/// run on Open Watch Party relays, not here.
const String plezyServerBaseUrl = isVexilyzeBuild ? '' : 'https://ice.plezy.app';
