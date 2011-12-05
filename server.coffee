connect = require 'connect'
fs = require 'fs'
universe = require './universe'

media = ['client.js', 'plain.css', 'jquery-1.7.1.min.js']

players = '42': new universe.Player

execute = (query, player) ->
    if query.verb == 'go'
        dir = query.arg.dir
        loc = player.get 'loc'
        room = universe.world.get('room_' + loc)
        if dir of room.exits
            newLoc = room.exits[dir]
            newRoom = universe.world.get('room_' + newLoc)
            if newRoom
                room = newRoom
                loc = newLoc
                player.set loc: loc
        desc = room.desc
        if room.exits
            desc += ' Exits:'
            for exit of room.exits
                desc += " #{exit}"
        return desc

handler = (req, resp) ->
    if req.method == 'POST'
        query = req.body.q
        user = req.body.u
        result = null
        if not user or user not of players
            result = error: 'No login.'
        else if typeof query != 'object'
            result = error: 'Bad query.'
        else
            try
                result = result: execute query, players[user]
            catch e
                console.error e
                result = error: 'Server error.'
        resp.writeHead 200, {'Content-Type': 'application/json'}
        resp.end JSON.stringify result
    # TEMP debug
    if req.url == '/'
        resp.writeHead 200
        resp.end fs.readFileSync 'index.html'
    else if req.url.slice(1) in media
        resp.writeHead 200
        resp.end fs.readFileSync req.url.slice(1)
    else
        resp.writeHead 404
        resp.end 'Not found'

server = connect.createServer connect.bodyParser(), handler
server.listen 8000
