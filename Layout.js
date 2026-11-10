// Preserve window order while trying different row capacities.
function rows(windows, columns) {
  var result = []
  for (var i = 0; i < windows.length; i += columns)
    result.push(windows.slice(i, i + columns))
  return result
}

// Choose the capacity that maximizes one shared scale while fitting the viewport.
// Gaps and the title/hint strip stay unscaled (24px and 30px respectively).
function arrange(windows, width, height) {
  if (!windows.length) return { rows: [], columns: 0, scale: 1, left: 0 }
  var best = null
  for (var columns = 1; columns <= windows.length; columns++) {
    var candidate = rows(windows, columns)
    var scale = Infinity, totalHeight = 0
    var rowWidths = []
    for (var r = 0; r < candidate.length; r++) {
      var totalWidth = 0, maxHeight = 1
      for (var i = 0; i < candidate[r].length; i++) {
        var size = candidate[r][i].size || [640, 400]
        totalWidth += Math.max(1, size[0])
        maxHeight = Math.max(maxHeight, size[1])
      }
      rowWidths.push(totalWidth)
      scale = Math.min(scale, (width - 24 * (candidate[r].length - 1)) / totalWidth)
      totalHeight += maxHeight
    }
    scale = Math.max(0, Math.min(scale, (height - 24 * (candidate.length - 1) - 30 * candidate.length) / totalHeight))
    if (best && scale <= best.scale) continue
    var maxWidth = 0
    for (var j = 0; j < candidate.length; j++)
      maxWidth = Math.max(maxWidth, rowWidths[j] * scale + 24 * (candidate[j].length - 1))
    best = { rows: candidate, columns: columns, scale: scale, left: Math.max(0, (width - maxWidth) / 2) }
  }
  return best
}
