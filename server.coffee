config = require './config'
connect = require 'connect'
fs = require 'fs'
universe = require './universe'

players = {}

plural = (word, count) ->
    if parseInt(count, 10) == 1 then word else "#{word}s"

world = new universe.World 1
world.getRoomCount (err, count) ->
    if err then throw err
    if not count
        world.allocRoom (err, id) ->
            if err then throw err
            world.createRoom id, {vis: {desc: 'You are at home.'}}, (err) ->
                if err then throw err
                world.setStartingRoom id, (err) ->
                    if err then throw err
                    console.log "Made initial room."
    else
        console.log "World has #{count} #{plural 'room', count}."

roomOf = (player) ->
    roomById player.get 'loc'

dirOpposites = north: 'south', south: 'north', west: 'east', east: 'west', up: 'down', down: 'up'

execute = (query, player, cb) ->
    switch query.verb
        when 'go'
            dir = query.arg.dir
            player.getRoom (err, room) ->
                if err then return cb err
                if room.exits and dir of room.exits
                    newLoc = room.exits[dir]
                    if newLoc
                        world.getRoom newLoc, (err, newRoom) ->
                            if err then return cb err
                            room = newRoom
                            player.loc = newLoc
                            cb null, look room
                        return
                cb null, "You can't go that way."

        when 'dig'
            dir = query.arg.dir
            backDir = dirOpposites[dir]
            if not dir or not backDir
                return cb null, "That's not a direction."
            oldId = player.loc

            # JESUS CHRIST HOW HORRIFYING
            # TODO: Coroutines or monads up in this bitch

            world.getRoom oldId, (err, oldRoom) ->
                if err then return cb err
                if not oldRoom.exits
                    oldRoom.exits = {}
                if dir of oldRoom.exits
                    return cb null, "That's already an exit."
                world.allocRoom (err, id) ->
                    if err then return cb err
                    newRoom = {exits: {}}
                    newRoom.exits[backDir] = oldId
                    world.createRoom id, newRoom, (err) ->
                        if err then return cb err
                        oldRoom.exits[dir] = id
                        world.updateRoom oldId, 'exits', oldRoom.exits, (err) ->
                            if err then return cb err
                            player.loc = id
                            cb null, 'Dug. ' + look newRoom

        when 'desc'
            newDesc = query.arg.desc.slice 0, 140
            player.getRoom (err, room) ->
                if err then return cb err
                if not room.vis
                    room.vis = {}
                room.vis.desc = newDesc
                world.updateRoom player.loc, 'vis', room.vis, (err) ->
                    if err
                        cb err
                    else
                        cb null, 'Changed. ' + look room
        when 'look'
            player.getRoom (err, room) ->
                if err then return cb err
                cb null, look room
        else
            cb null, "What?"

look = (room) ->
    desc = room.vis?.desc or "Can't see shit captain."
    if room.exits
        desc += ' Exits:'
        for exit of room.exits
            desc += " #{exit}"
    desc

handler = (req, resp) ->
    if req.method == 'POST'
        query = req.body.q
        user = req.body.u
        result = null
        reply = (packet) ->
            resp.writeHead 200, {'Content-Type': 'application/json'}
            resp.end JSON.stringify packet
        if not user
            reply error: 'No login.'
        else if typeof query != 'object'
            reply error: 'Bad query.'
        else
            doIt = (player, prefix) ->
                try
                    execute query, player, (err, msg) ->
                        if err
                            console.error err?.stack or err
                            reply error: 'Game error.'
                        else
                            reply result: "#{prefix}#{msg}"
                catch e
                    console.error e.stack
                    reply error: 'Server error.'

            if user of players
                doIt players[user], ''
            else
                player = new universe.Player
                player.enterWorld world, (err) ->
                    if err
                        console.error err
                        reply error: "Couldn't enter world."
                    else
                        players[user] = player
                        doIt player, 'Welcome. '
        return
    # TEMP debug
    if config.DEBUG
        name = req.url.slice 1
        if name == ''
            resp.writeHead 200, {'Content-Type': 'text/html; charset=UTF-8'}
            resp.end fs.readFileSync 'index.html'
        else if name in media
            mime = if name.match /\.js$/ then 'application/javascript' else 'text/css'
            resp.writeHead 200, {'Content-Type': mime}
            resp.end fs.readFileSync req.url.slice(1)
        else
            resp.writeHead 404
            resp.end 'Not found'

media = ['client.js', 'plain.css', 'jquery-1.7.1.min.js', 'input.js']

server = connect.createServer connect.bodyParser(), handler
server.listen config.PORT
