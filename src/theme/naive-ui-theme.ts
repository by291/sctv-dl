import type { GlobalThemeOverrides } from 'naive-ui'

// Naive UI derives hover and focus colors from these values with its own color
// parser, so the palette must stay in literal notation rather than CSS variables.
const fontFamily =
  '-apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB", "Noto Sans SC", "Microsoft YaHei", "Segoe UI", sans-serif'

function createThemeOverrides(palette: {
  bg: string
  panel: string
  text: string
  muted: string
  line: string
  accent: string
  accentHover: string
  accentPressed: string
  fill: string
  fillHover: string
  fillPressed: string
}): GlobalThemeOverrides {
  return {
    common: {
      bodyColor: palette.bg,
      cardColor: palette.panel,
      modalColor: palette.panel,
      popoverColor: palette.panel,
      textColor1: palette.text,
      textColor2: palette.text,
      textColor3: palette.muted,
      borderColor: palette.line,
      dividerColor: palette.line,
      primaryColor: palette.accent,
      primaryColorHover: palette.accentHover,
      primaryColorPressed: palette.accentPressed,
      primaryColorSuppl: palette.accentHover,
      borderRadius: '6px',
      // Naive UI writes this into its global body rule before application styles load.
      fontFamily,
      fontSize: '15px',
      fontSizeSmall: '13px',
      fontSizeMedium: '15px',
      fontSizeLarge: '17px',
      fontSizeHuge: '19px',
      heightSmall: '34px',
      heightMedium: '40px',
      heightLarge: '46px',
    },
    Button: {
      fontWeight: '500',
      colorPrimary: palette.fill,
      colorHoverPrimary: palette.fillHover,
      colorPressedPrimary: palette.fillPressed,
      colorFocusPrimary: palette.fillHover,
    },
    Badge: { color: palette.fill },
    Modal: {
      peers: {
        Card: {
          closeSize: '32px',
        },
      },
    },
  }
}

export const lightThemeOverrides = createThemeOverrides({
  bg: '#f2f4ee',
  panel: '#ffffff',
  text: '#1b1f1c',
  muted: '#687167',
  line: '#dce0d7',
  accent: '#c1352a',
  accentHover: '#d24638',
  accentPressed: '#a82a21',
  fill: '#c1352a',
  fillHover: '#a82a21',
  fillPressed: '#8f221b',
})

export const darkThemeOverrides = createThemeOverrides({
  bg: '#111613',
  panel: '#191f1b',
  text: '#e8ebe3',
  muted: '#98a196',
  line: '#2b332d',
  accent: '#e46455',
  accentHover: '#ef7a6b',
  accentPressed: '#c95345',
  fill: '#c1352a',
  fillHover: '#a82a21',
  fillPressed: '#8f221b',
})
