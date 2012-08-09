Range = require 'range'
TextMateBundle = require 'text-mate-bundle'
_ = require 'underscore'
require 'underscore-extensions'

module.exports =
class LanguageMode
  pairedCharacters:
    '(': ')'
    '[': ']'
    '{': '}'
    '"': '"'
    "'": "'"

  constructor: (@editSession) ->
    @grammar = TextMateBundle.grammarForFileName(@editSession.buffer.getBaseName())

    _.adviseBefore @editSession, 'insertText', (text) =>
      return true if @editSession.hasMultipleCursors()

      cursorBufferPosition = @editSession.getCursorBufferPosition()
      nextCharachter = @editSession.getTextInBufferRange([cursorBufferPosition, cursorBufferPosition.add([0, 1])])

      if @isCloseBracket(text) and text == nextCharachter
        @editSession.moveCursorRight()
        false
      else if pairedCharacter = @pairedCharacters[text]
        @editSession.insertText text + pairedCharacter
        @editSession.moveCursorLeft()
        false

  isOpenBracket: (string) ->
    @pairedCharacters[string]?

  isCloseBracket: (string) ->
    @getInvertedPairedCharacters()[string]?

  getInvertedPairedCharacters: ->
    return @invertedPairedCharacters if @invertedPairedCharacters

    @invertedPairedCharacters = {}
    for open, close of @pairedCharacters
      @invertedPairedCharacters[close] = open
    @invertedPairedCharacters

  toggleLineCommentsInRange: (range) ->
    selectedBufferRanges = @editSession.getSelectedBufferRanges()
    range = Range.fromObject(range)
    range = new Range([range.start.row, 0], [range.end.row, Infinity])
    scopes = @tokenizedBuffer.scopesForPosition(range.start)
    commentString = TextMateBundle.lineCommentStringForScope(scopes[0])
    commentSource = "^(\s*)" + _.escapeRegExp(commentString)

    text = @editSession.getTextInBufferRange(range)
    isCommented = new RegExp(commentSource).test text

    if isCommented
      text = text.replace(new RegExp(commentSource, "gm"), "$1")
    else
      text = text.replace(/^/gm, commentString)

    @editSession.setTextInBufferRange(range, text)
    @editSession.setSelectedBufferRanges(selectedBufferRanges)

  doesBufferRowStartFold: (bufferRow) ->
    return false if @editSession.isBufferRowBlank(bufferRow)
    nextNonEmptyRow = @editSession.nextNonBlankBufferRow(bufferRow)
    return false unless nextNonEmptyRow?
    @editSession.indentationForBufferRow(nextNonEmptyRow) > @editSession.indentationForBufferRow(bufferRow)

  rowRangeForFoldAtBufferRow: (bufferRow) ->
    return null unless @doesBufferRowStartFold(bufferRow)

    startIndentation = @editSession.indentationForBufferRow(bufferRow)
    for row in [(bufferRow + 1)..@editSession.getLastBufferRow()]
      continue if @editSession.isBufferRowBlank(row)
      indentation = @editSession.indentationForBufferRow(row)
      if indentation <= startIndentation
        includeRowInFold = indentation == startIndentation and @grammar.foldEndRegex.search(@editSession.lineForBufferRow(row))
        foldEndRow = row if includeRowInFold
        break

      foldEndRow = row

    [bufferRow, foldEndRow]

  indentationForRow: (row) ->
    for precedingRow in [row - 1..-1]
      return if precedingRow < 0
      precedingLine = @editSession.buffer.lineForRow(precedingRow)
      break if /\S/.test(precedingLine)

    scopes = @tokenizedBuffer.scopesForPosition([precedingRow, Infinity])
    indentation = precedingLine.match(/^\s*/)[0]
    increaseIndentPattern = TextMateBundle.getPreferenceInScope(scopes[0], 'increaseIndentPattern')
    decreaseIndentPattern = TextMateBundle.getPreferenceInScope(scopes[0], 'decreaseIndentPattern')

    if new OnigRegExp(increaseIndentPattern).search(precedingLine)
      indentation += @editSession.tabText

    line = @editSession.buffer.lineForRow(row)
    if new OnigRegExp(decreaseIndentPattern).search(line)
      indentation = indentation.replace(@editSession.tabText, "")

    indentation

  getLineTokens: (line, stack) ->
    {tokens, stack} = @grammar.getLineTokens(line, stack)

