$log = $ 'article'
$line = $ 'b'
$entryArea = $ 'b span'
$input = $entryArea.find 'input'
$suggest = $entryArea.find 'ol'

lastSugs = []
cardinals = ['north', 'south', 'east', 'west']

DEBUG = false
if DEBUG
    $debug = $('<div/>').css({'margin-top': '10em'}).insertAfter $line

userId = null

sentence = []
root = pos = null

execute = ->
    flat = (t for t in flatten root when typeof t == 'string')
    feedback flat.join ' '
    strip root
    $.ajax
        type: 'POST',
        data: {q: root, u: userId},
        dataType: 'json',
        headers: {Accept: 'application/json'}
        success: (data, status, $xhr) ->
            if data.error
                logError data.error
            else
                feedback data.result
        error: ($xhr, textStatus, error) ->
            logError "Couldn't connect to server."

strip = (node) ->
    if typeof node == 'object'
        delete node.up
        delete node.done
        for k, v of node
            strip v

backUp = ->
    seen = []
    while not pos.need
        if pos.up
            if pos in seen
                logError "Couldn't construct command."
                break
            seen.push pos
            pos = pos.up
        else
            pos.done = true
            break

$input.on 'keydown', (event) -> scrollLock ->
    box = $input[0]
    atLeft = box.selectionStart == 0 and box.selectionEnd == 0
    len = $input.val().length
    atRight = box.selectionStart == len and box.selectionEnd == len

    if event.which == 8
        if atLeft
            backspace()
            construct()

    changed = false

    if pos.need != 'desc'
        # One-word completion
        if event.which in [9, 13, 32]
            event.preventDefault()
            # Try to complete
            val = $input.val()
            if event.which == 9 and lastSugs.length == 1
                val = lastSugs[0]
            changed = tryChoice val
    else
        # Free-form description
        if event.which in [9, 13]
            event.preventDefault()
            delete pos.need
            pos.desc = $input.val()
            backUp()
            changed = true

    if event.which == 13 and root.done
        execute()
        reset()
        changed = true
    if changed
        $input.val ''
        construct()
    ###
    else if event.which == 37
        if atLeft
            feedback 'left'
    else if event.which == 39
        if atRight
            feedback 'right'
    ###

suggest = ->
    word = $input.val()
    if not DEBUG and not word
        $suggest.hide()
        return
    sugs = []
    switch pos.need
        when 'desc'
            $suggest.hide()
            return
        when 'verb'
            sugs = ['go', 'desc', 'dig', 'look']
        when 'dir'
            sugs = cardinals
    sugs = (sug for sug in sugs when sug.indexOf(word) == 0)
    sugs.sort()
    $suggest.empty()
    empty = true
    for sug in sugs
        $('<li/>').text(sug).appendTo $suggest
        empty = false
    lastSugs = sugs
    if empty then $suggest.hide() else $suggest.show()

$input.input -> scrollLock -> suggest()

$entryArea.on 'click', 'li', (event) -> scrollLock ->
    event.preventDefault()
    if tryChoice $(event.target).text()
        $input.val ''
        construct()
        suggest()

tryChoice = (word) ->
    orig = pos
    origDone = pos.done
    choose word
    if orig != pos or origDone != pos.done
        $suggest.hide()
        true
    else
        false

choose = (word) ->
    orig = pos
    if pos.need == 'verb'
        found = true
        if word in ['go', 'dig']
            pos.verb = word
            pos.arg = up: pos, need: 'dir'
            pos = pos.arg
        else if word == 'desc'
            pos.verb = word
            pos.arg = up: pos, need: 'desc'
            pos = pos.arg
        else if word == 'look'
            pos.verb = 'look'
            pos.done = true
        else
            found = false
    else if pos.need == 'dir'
        if word in cardinals
            delete pos.need
            pos.dir = word
            backUp()
        else
            found = false
    else if pos.need == 'desc'
        # shouldn't get here?
    else
        found = false

    if found
        delete orig.need


backspace = ->
    target = pos
    if target.done
        delete target.done
        # Find last child
        if target.arg
            pos = target.arg
            if pos.dir
                $input.val (pos.dir + ' ')
                delete pos.dir
                pos.need = 'dir'
            else if pos.desc
                $input.val (pos.desc + ' ')
                delete pos.desc
                pos.need = 'desc'
        else
            $input.val (target.verb + ' ')
            target.need = 'verb'
            delete target.verb
    else if target.need
        # Delete this
        if target.up
            parent = target.up
            if parent.arg is target
                pos = parent
                $input.val (pos.verb + ' ')
                delete pos.arg
                delete pos.verb
                pos.need = 'verb'

scrollLock = (f) ->
    $doc = $ document
    orig = $doc.height()
    ret = f.call this
    height = $doc.height()
    if height > orig
        window.scrollBy 0, height - orig + 1

feedback = (msg) ->
    $log.append $('<p/>').text msg

logError = (msg) ->
    $log.append $('<p class="error"/>').text msg

vis = ['need', 'verb', 'dir', 'arg', 'desc']

visualize = (node) ->
    $ul = $ '<ul/>'
    for attr in vis
        val = node[attr]
        if not val
            continue
        if typeof val == 'string'
            $ul.append $('<li>').text("#{attr} #{val}")
        else if typeof val == 'object'
            $ul.append $('<li>').text(attr).append(visualize(val))
    if node.done
        $ul.css color: 'green'
    else if node == pos
        $ul.css color: 'blue'
    $ul

flatten = (root) ->
    flat = ["> "]
    go = (node) ->
        if node.need
            flat.push $entryArea
        else if node.verb
            flat.push node.verb
            if node.arg
                go node.arg
        else if node.dir
            flat.push node.dir
        else if node.desc
            flat.push "\"#{node.desc}\""
        if node.done
            flat.push $entryArea
    go root
    flat

construct = ->
    if DEBUG
        $debug.children().remove()
        $debug.append visualize(root)
    flat = flatten root, flat
    $entryArea.detach() # Don't want to lose our attached events
    $line.empty()
    for bit in flat
        if typeof bit == 'string'
            $line.append document.createTextNode (bit + ' ')
        else
            $line.append bit

    if pos.done
        $line.attr class: 'done'
    else
        $line.removeAttr 'class'
    if pos.need == 'desc'
        $entryArea.attr class: 'desc'
    else
        $entryArea.removeAttr 'class'
    $input.focus()

reset = ->
    root = {need: 'verb'}
    pos = root

loadAccount = ->
    userId = '42'

$(document).ready ->
    loadAccount()
    reset()
    construct()
    suggest()
