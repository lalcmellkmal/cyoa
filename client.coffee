$input = $ 'input'
$log = $ 'article'
$debug = $ 'div'
$line = $ 'b'

sentence = []
root = pos = null

backUp = () ->
    seen = []
    while not pos.need
        if pos.up
            if pos in seen
                console.error 'infinite loop'
                break
            seen.push pos
            pos = pos.up
        else
            pos.done = true
            break

$input.on 'keydown', (event) ->
    box = $input[0]
    atLeft = box.selectionStart == 0 and box.selectionEnd == 0
    len = $input.val().length
    atRight = box.selectionStart == len and box.selectionEnd == len
    if event.which == 13 and root.done
        reset()
        $input.val ''
        feedback 'Okay.'
        construct()
        return
    if event.which in [9, 13, 32]
        event.preventDefault()
        word = $input.val()
        $input.val ''
        orig = pos
        choose word
        if orig != pos
            # state updated
            construct()
        else
            feedback 'What?'
    else if event.which == 8
        if atLeft
            backspace()
            construct()
    ###
    else if event.which == 37
        if atLeft
            feedback 'left'
    else if event.which == 39
        if atRight
            feedback 'right'
    ###

choose = (word) ->
    if pos.need == 'verb'
        if word == 'go'
            delete pos.need
            pos.verb = 'go'
            pos.arg = up: pos, need: 'dir'
            pos = pos.arg
    else if pos.need == 'dir'
        if word in ['north', 'south', 'east', 'west']
            delete pos.need
            pos.dir = word
            backUp()

backspace = () ->
    target = pos
    if target.done
        # Find last child
        if target.arg
            delete target.done
            pos = target.arg
            $input.val (pos.dir + ' ')
            delete pos.dir
            pos.need = 'dir'
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

feedback = (msg) ->
    $log.append $('<p/>').text msg

vis = ['need', 'verb', 'dir', 'arg']

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

construct = () ->
    $debug.children().remove()
    $debug.append visualize(root)
    flat = []
    go = (node) ->
        if node.need
            flat.push $input
        else if node.verb
            flat.push node.verb
            go node.arg
        else if node.dir
            flat.push node.dir
        if node.done
            flat.push $input
    go root
    $input.detach()
    $line.empty()
    for bit in flat
        if typeof bit == 'string'
            $line.append document.createTextNode (bit + ' ')
        else
            $line.append bit
    $input.focus()

reset = () ->
    root = {need: 'verb'}
    pos = root

$(document).ready () ->
    reset()
    construct()
