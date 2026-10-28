// Kanagawa Dragon for Blink Shell, with a pure black background for OLED.
// Palette and foreground match Ghostty's built-in "Kanagawa Dragon" theme;
// only the background (#181616 there) is changed.
black       = '#0d0c0c';
red         = '#c4746e';
green       = '#8a9a7b';
yellow      = '#c4b28a';
blue        = '#8ba4b0';
magenta     = '#a292a3';
cyan        = '#8ea4a2';
white       = '#c8c093';
lightBlack  = '#a6a69c';
lightRed    = '#e46876';
lightGreen  = '#87a987';
lightYellow = '#e6c384';
lightBlue   = '#7fb4ca';
lightMagenta = '#938aa9';
lightCyan   = '#7aa89f';
lightWhite  = '#c5c9c5';

t.prefs_.set('color-palette-overrides',
  [black, red, green, yellow, blue, magenta, cyan, white,
   lightBlack, lightRed, lightGreen, lightYellow, lightBlue, lightMagenta, lightCyan, lightWhite]);

t.prefs_.set('cursor-color', 'rgba(200, 192, 147, 0.5)');
t.prefs_.set('foreground-color', '#c5c9c5');
t.prefs_.set('background-color', '#000000');
