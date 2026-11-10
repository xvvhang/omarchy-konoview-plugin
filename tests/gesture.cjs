const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const source = fs.readFileSync(path.join(__dirname, '../Main.qml'), 'utf8')
const start = source.indexOf('  function press() {')
const end = source.indexOf('  function toggle()', start)
assert.ok(start >= 0 && end > start)
let now = 1000, toggles = 0
const context = vm.createContext({
  Date: { now: () => now }, lastTap: 0, tapCount: 0, pressCount: 0, lastTapInterval: 0,
  suppressNextTap: false, listing: { running: false }, toggle: () => toggles++,
})
vm.runInContext(source.slice(start, end), context)
context.press()
assert.equal(toggles, 0)
now += 50
context.tap()
assert.equal(toggles, 0)
now += 100
context.press()
assert.equal(toggles, 1, 'Toggle on second press, without waiting for release')
now += 50
context.tap()
assert.equal(toggles, 1)
assert.equal(context.lastTap, 0, 'Second release must not re-arm')
// A first Super chord has no lone-release event and cannot arm the gesture.
now += 1000
context.press()
now += 100
context.press()
assert.equal(toggles, 1)
context.tap()
now += 350
context.press()
assert.equal(toggles, 1, 'An expired interval must not toggle')
// Legacy release-only bindings retain their behavior.
now += 1000
context.tap()
now += 100
context.tap()
assert.equal(toggles, 2)
// Recover when an exclusive-layer transition swallowed the suppressed release.
now += 1000
context.tap()
now += 100
context.press()
assert.equal(toggles, 3)
now += 1000
context.press()
context.tap()
now += 100
context.press()
assert.equal(toggles, 4)
console.log('Second-press gesture tests passed')
