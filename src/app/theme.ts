import type { GlobalThemeOverrides } from 'naive-ui'

export const themeOverrides: GlobalThemeOverrides = {
  common: {
    primaryColor: '#dc4f41',
    primaryColorHover: '#e5685b',
    primaryColorPressed: '#be3f34',
    borderRadius: '8px',
    fontFamily: 'Inter, "Segoe UI", "Microsoft YaHei", sans-serif',
  },
  Button: { fontWeight: '600', heightMedium: '38px', heightLarge: '44px' },
}
