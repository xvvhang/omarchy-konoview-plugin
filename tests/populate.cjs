const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')

const source = fs.readFileSync(path.join(__dirname, '../Main.qml'), 'utf8')
const start = source.indexOf('  function populate(text) {')
const end = source.indexOf('  function handleFor(', start)
assert.ok(start >= 0 && end > start)
const context = vm.createContext({
  opened: true, windows: [], cachedClients: '', focusedAddress: '',
  hint: index => String(index), errorText: '', populateMs: 0,
  cachedPreviews: {}, cacheKey: w => w.address + ':' + w.pid,
})
vm.runInContext(source.slice(start, end), context)
const client = { address: '0x1', mapped: true, title: 'One', class: 'Terminal', workspace: { id: 1, name: '1' }, size: [1000, 600], focusHistoryID: 0 }
const populate = clients => context.populate(JSON.stringify(clients))
populate([client])
const original = context.windows
context.cachedPreviews[context.cacheKey(client)] = { url: 'image://test/one' }
populate([{ ...client, focusHistoryID: 1, at: [10, 10] }])
assert.equal(context.windows, original, 'Unchanged previews must not be recreated')
assert.ok(context.cachedPreviews[context.cacheKey(client)])
for (const changed of [{ title: 'Two' }, { size: [800, 600] }, { workspace: { id: 2, name: '2' } }, { class: 'Browser' }, { address: '0x2' }]) {
  populate([{ ...client, ...changed }])
  assert.notEqual(context.windows, original)
  populate([client])
}
populate([])
assert.equal(context.windows.length, 0)
assert.equal(Object.keys(context.cachedPreviews).length, 0)
assert.equal(context.errorText, '')
console.log('Preview model reuse tests passed')

const cacheStart = source.indexOf('  function cacheKey(')
const cacheEnd = source.indexOf('  function hint(', cacheStart)
assert.ok(cacheStart >= 0 && cacheEnd > cacheStart)
context.snapshotGeneration = 1
vm.runInContext(source.slice(cacheStart, cacheEnd), context)
context.storeSnapshot('stale', { url: 'image://test/stale' }, 0)
assert.equal(context.cachedPreviews.stale, undefined)
for (let i = 0; i < 100; i++) context.storeSnapshot(String(i), { url: 'image://test/' + i }, 1)
assert.equal(Object.keys(context.cachedPreviews).length, 64)
assert.ok(context.cachedPreviews['99'])
console.log('Thumbnail cache bounds and stale-callback tests passed')
