import type { GlobalThemeOverrides } from 'naive-ui'

export const themeOverrides: GlobalThemeOverrides = {
  common: {
    bodyColor: 'var(--bg)',
    textColor2: 'var(--text)',
    primaryColor: '#dc4f41',
    primaryColorHover: '#e5685b',
    primaryColorPressed: '#be3f34',
    borderRadius: '8px',
    fontFamily: 'Inter, "Segoe UI", "Microsoft YaHei", sans-serif',
    fontSize: '16px',
    fontSizeSmall: '14px',
    fontSizeMedium: '16px',
    fontSizeLarge: '18px',
    heightSmall: '36px',
    heightMedium: '42px',
    heightLarge: '48px',
  },
  Button: { fontWeight: '600' },
  Modal: {
    peers: {
      Card: {
        closeSize: '32px',
      },
    },
  },
}
