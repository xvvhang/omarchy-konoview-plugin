const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const layout = vm.createContext({})
vm.runInContext(fs.readFileSync(path.join(__dirname, '../Layout.js'), 'utf8'), layout)

function check(windows, width, height) {
  const result = layout.arrange(windows, width, height)
  assert.ok(Number.isFinite(result.scale) && result.scale > 0)
  assert.deepEqual(Array.from(result.rows.flat()), windows)
  let usedHeight = 24 * Math.max(0, result.rows.length - 1)
  for (const row of result.rows) {
    const sizes = row.map(w => w.size || [640, 400])
    const usedWidth = sizes.reduce((sum, s) => sum + s[0] * result.scale, 0) + 24 * (row.length - 1)
    assert.ok(result.left + usedWidth <= width + 1e-7)
    usedHeight += Math.max(...sizes.map(s => s[1])) * result.scale + 30
    for (const size of sizes)
      assert.ok(Math.abs((size[0] * result.scale) / (size[1] * result.scale) - size[0] / size[1]) < 1e-7)
  }
  assert.ok(usedHeight <= height + 1e-7)
  return result
}

assert.equal(layout.arrange([], 1200, 800).rows.length, 0)
for (const count of [1, 5, 6, 7, 9, 10, 11, 20]) {
  const windows = Array.from({ length: count }, () => ({ size: [1000, 600] }))
  for (const [width, height] of [[1200, 800], [2400, 600], [600, 1600]])
    check(windows, width, height)
}
const windows = Array.from({ length: 8 }, () => ({ size: [1000, 600] }))
assert.ok(check(windows, 2400, 600).columns > check(windows, 600, 1600).columns)
assert.ok(check(windows, 6000, 600).columns > 5)
check([{ size: [2000, 600] }, { size: [500, 1800] }, {}, ...windows], 1200, 800)
console.log('Dynamic layout/shared-scale tests passed')
