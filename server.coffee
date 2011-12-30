connect = require 'connect'
fs = require 'fs'
universe = require './universe'

media = ['client.js', 'plain.css', 'jquery-1.7.1.min.js', 'input.js']

players = '42': new universe.Player

world = null
universe.loadWorld (err, w, count) ->
    if err then throw err
    world = w
    if count == 0
        universe.addSimpleRooms world, (err) ->
            if err then throw err
            universe.saveWorld world, (err) ->
                if err then throw err

roomById = (id) ->
    world.get id

roomOf = (player) ->
    roomById player.get 'loc'

dirOpposites = north: 'south', south: 'north', west: 'east', east: 'west'

execute = (query, player, cb) ->
    switch query.verb
        when 'go'
            dir = query.arg.dir
            room = roomOf player
            if room.exits and dir of room.exits
                newLoc = room.exits[dir]
                newRoom = world.get newLoc
                if newRoom
                    room = newRoom
                    player.set loc: newLoc
                    return cb null, look room
            cb null, "You can't go that way."
        when 'dig'
            dir = query.arg.dir
            backDir = dirOpposites[dir]
            if not dir or not backDir
                return cb null, "That's not a direction."
            oldId = player.get 'loc'
            room = roomById oldId
            if not room.exits
                room.exits = {}
            if dir of room.exits
                return cb null, "That's already an exit."
            newRoom = {exits: {}}
            world.createRoom newRoom, (err, id) ->
                if err
                    cb err
                else
                    room.exits[dir] = id
                    newRoom.exits[backDir] = oldId
                    universe.saveWorld world, (err) ->
                        if err
                            # Should really delete the botched room
                            # but whatever we're getting rid of save()
                            # soon enough
                            cb err
                        else
                            player.set loc: id
                            cb null, 'Dug. ' + look newRoom
        when 'desc'
            newDesc = query.arg.desc.slice 0, 140
            room = roomOf player
            if not room.vis
                room.vis = {}
            room.vis.desc = newDesc
            universe.saveWorld world, (err) ->
                if err
                    cb err
                else
                    cb null, 'Changed. ' + look room
        when 'look'
            cb null, look roomOf player
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
        if not user or user not of players
            reply error: 'No login.'
        else if typeof query != 'object'
            reply error: 'Bad query.'
        else
            try
                execute query, players[user], (err, msg) ->
                    if err
                        console.error err
                        reply error: 'Game error.'
                    else
                        reply result: msg
            catch e
                console.error e
                reply error: 'Server error.'
        return
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
