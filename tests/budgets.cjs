const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const source = fs.readFileSync(path.join(__dirname, '../Main.qml'), 'utf8')
const start = source.indexOf('readonly property var captureAddresses: {')
const end = source.indexOf('  property double openStartedAt:', start)
assert.ok(start >= 0 && end > start)
const body = source.slice(source.indexOf('{', start) + 1, source.lastIndexOf('}', end))
const context = vm.createContext({
  filteredWindows: [], priorityAddress: '0x50', maxCaptures: 12,
  targetScreen: { name: 'test' }, Hyprland: { monitors: { values: [{ name: 'test', scale: 2 }] } },
})
vm.runInContext('function captures() {' + body + '}', context)
context.filteredWindows = Array.from({ length: 128 }, (_, i) => ({ address: '0x' + i, size: [640, 400] }))
assert.equal(context.captures().length, 12)
assert.equal(context.captures()[0], '0x50')
context.filteredWindows = Array.from({ length: 128 }, (_, i) => ({ address: '0x' + i, size: [2000, 2000] }))
assert.equal(context.captures().length, 3, '48 MiPixel total budget')
context.filteredWindows = [{ address: 'huge', size: [10000, 10000] }, { address: 'small', size: [640, 400] }]
assert.deepEqual(Array.from(context.captures()), ['small'], 'Reject over-budget source before assigning a capture')
console.log('Capture count and source-pixel budget tests passed')
