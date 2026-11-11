import QtQuick

Text {
  property string appClass: ""
  textFormat: Text.PlainText
  text: (appClass || "Window").slice(0, 256).replace(/[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]/g, " ") + "\nPreview unavailable"
}
