/// Independent TV build configuration. The owner keeps the Plezy display name
/// for personal installations; update and service identities remain separate.
const isVexilyzeBuild = bool.fromEnvironment('VEXILYZE_BUILD');
const appDisplayName = 'Plezy';
const appLinkScheme = isVexilyzeBuild ? 'vexilyzetv' : 'plezy';

/// The upstream project's OAuth registrations and hosted services belong to
/// that project. The fork does not offer them until it has its own registrations.
const upstreamIntegrationsAvailable = !isVexilyzeBuild;
