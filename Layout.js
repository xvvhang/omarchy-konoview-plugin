// Fill each row with up to five windows, preserving their order.
function rows(windows) {
  var result = []
  for (var i = 0; i < windows.length; i += 5)
    result.push(windows.slice(i, i + 5))
  return result
}
