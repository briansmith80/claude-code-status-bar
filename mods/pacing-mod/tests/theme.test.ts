import { expect, test } from 'claude-code/testing'
import { THEMES, fillFor, parseConf, resolveLook } from '../hooks/theme'

test('reads the theme the way bash sources the conf', () => {
  const look = parseConf('# colour_theme=nord\ncolour_theme=dracula\nbar_gradient="heat"\n')
  expect(look.theme).toBe(THEMES.dracula)
  expect(look.gradient).toBe('heat')
  expect(parseConf('colour_theme=nope').theme).toBe(THEMES.default)
})

test('the theme option pins a palette over the conf, status-bar follows it', () => {
  expect(resolveLook('colour_theme=nord', 'status-bar').theme).toBe(THEMES.nord)
  expect(resolveLook('colour_theme=nord', 'matrix').theme).toBe(THEMES.matrix)
  expect(resolveLook(null, 'status-bar').theme).toBe(THEMES.default)
  expect(resolveLook('colour_theme=nord\nbar_gradient=false', 'matrix').gradient).toBe('false')
})

test('flat bars use the severity colour, mono has no gradient', () => {
  expect(fillFor({ theme: THEMES.nord!, gradient: 'false' }, 85)).toEqual(['#bf616a'])
  expect(fillFor({ theme: THEMES.mono!, gradient: 'true' }, 10)).toEqual(['#9aa4b2'])
})
