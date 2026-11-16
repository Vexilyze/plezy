/// Public fork identity. Release builds set VEXILYZE_BUILD so upstream tests
/// and other platform build configurations keep their existing contracts.
const isVexilyzeBuild = bool.fromEnvironment('VEXILYZE_BUILD');
const appDisplayName = isVexilyzeBuild ? 'Vexilyze TV' : 'Plezy';
const appLinkScheme = isVexilyzeBuild ? 'vexilyzetv' : 'plezy';

/// The upstream project's OAuth registrations and hosted services belong to
/// that project. The fork does not offer them until it has its own registrations.
const upstreamIntegrationsAvailable = !isVexilyzeBuild;
