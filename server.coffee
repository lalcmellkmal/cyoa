connect = require 'connect'
fs = require 'fs'
universe = require './universe'

U = universe.U

media = ['client.js', 'plain.css', 'jquery-1.7.1.min.js']

players = '42': new universe.Player

roomOf = (player, cb) ->
    loc = player.get 'loc'
    U.get universe.Room, loc, (err, room) ->
        if err then throw err
        else cb room

dirOpposites = north: 'south', south: 'north', west: 'east', east: 'west'

execute = (query, player, callback) ->
    okay = (msg) -> callback null, msg
    switch query.verb
        when 'go'
            dir = query.arg.dir
            roomOf player, (room) ->
                if room.exits and dir of room.exits
                    newLoc = room.exits[dir]
                    U.get universe.Room, newLoc, (err, newRoom) ->
                        if err then throw err
                        room = newRoom
                        player.set loc: newLoc
                        return okay look room
                else
                    okay "You can't go that way."
        when 'dig'
            dir = query.arg.dir
            backDir = dirOpposites[dir]
            if not dir or not backDir
                return okay "That's not a direction."
            roomOf player, (oldRoom) ->
                if dir of oldRoom.exits
                    return okay "That's already an exit."
                U.create universe.Room, (err, newRoom) ->
                    if err then throw err
                    oldRoom.exits[dir] = newRoom.id
                    newRoom.exits[backDir] = oldRoom.id
                    m = U.begin()
                    m.save universe.Room, oldRoom
                    m.save universe.Room, newRoom
                    m.end (err) ->
                        if err then throw err
                        #player.set loc: newRoom.id
                        okay 'Dug.'
        when 'look'
            roomOf player, (room) ->
                okay look room
        else
            okay "What?"

look = (room) ->
    vis = room.get 'vis'
    desc = "Can't see shit captain."
    if vis and vis.desc
        desc = vis.desc
    if room.exits
        desc += ' Exits:'
        for exit of room.get 'exits'
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
                reply error: 'Server error.'
                throw e # debug
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
