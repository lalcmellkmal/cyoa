config = require './config'
Backbone = require 'backbone'
redis = require 'redis'
async = require 'async'

redisClient = ->
    require('redis').createClient(config.REDIS_PORT)

db = redisClient()

class World extends Backbone.Model
    initialize: (rooms) ->
        @set rooms

    createRoom: (room, cb) ->
        db.incr "roomCtr", (err, id) =>
            if err then return cb err
            if @has id
                return cb "Room of id #{id} already exists!"
            info = {}
            info[id] = room
            @set info
            cb null, id

class Player extends Backbone.Model
    initialize: ->
        @set loc: 1
exports.Player = Player

exports.loadWorld = (cb) ->
    worldIndex = 1
    key = "world:#{worldIndex}"
    db.smembers "#{key}:rooms", (err, roomNumbers) ->
        if err
            cb err
        roomMap = {}
        count = 0
        loadRoom = (id, cb) ->
            db.hgetall "room:#{id}", (err, roomBlob) ->
                if err
                    return cb err
                room = {}
                for key, val of roomBlob
                    room[key] = JSON.parse val
                roomMap[id] = room
                count++
                cb null
        async.forEach roomNumbers, loadRoom, (err) ->
            if err
                return cb err
            world = new World roomMap
            console.log "Loaded #{count} rooms."
            cb null, world, count

exports.addSimpleRooms = (world, cb) ->
    world.set
        1: {vis: {desc: 'You are at home.'}, exits: {north: 2}}
        2: {vis: {desc: 'You are outside.'}, exits: {south: 1}}
    db.get 'roomCtr', (err, count) ->
        if err
            cb err
        else if count < 2
            db.set 'roomCtr', 2, cb
        else
            cb null

exports.saveWorld = (world, cb) ->
    worldIndex = 1
    m = db.multi()
    roomIds = []
    count = 0
    for id, roomObj of world.attributes
        roomIds.push id
        room = {}
        for key, val of roomObj
            room[key] = JSON.stringify val
        roomKey = "room:#{id}"
        m.del roomKey
        m.hmset roomKey, room
        count++
    key = "world:#{worldIndex}"
    roomsKey = "#{key}:rooms"
    m.del roomsKey
    m.sadd roomsKey, roomIds
    m.exec (err, rs) ->
        if not err
            console.log "Saved #{count} rooms."
        cb err
