_ = require 'underscore'
config = require './config'
redis = require 'redis'

redisClient = ->
    require('redis').createClient(config.REDIS_PORT)

db = redisClient()

class World
    constructor: (worldIndex) ->
        @worldKey = "world:#{worldIndex}"

    allocRoom: (cb) ->
        db.incr "roomCtr", (err, id) =>
            if err then cb err else cb null, id

    createRoom: (id, room, cb) ->
        key = "room:#{id}"
        db.exists key, (err, exists) =>
            if err then return cb err
            if exists then return cb "Room ##{id} already exists!"
            info = {}
            for k, v of room
                info[k] = JSON.stringify v
            m = db.multi()
            m.hmset key, info
            m.sadd "#{@worldKey}:rooms", id
            m.exec cb

    updateRoom: (id, k, v, cb) ->
        key = "room:#{id}"
        db.exists key, (err, exists) ->
            if err then return cb err
            if not exists then return cb "No room ##{id}"
            db.hset key, k, JSON.stringify(v), cb

    getRoom: (id, cb) ->
        db.hgetall "room:#{id}", (err, info) =>
            if err then return cb err
            if _.isEmpty info then return cb "No such room."
            room = {}
            try
                for k, v of info
                    room[k] = JSON.parse v
            catch e
                return cb e
            cb null, room

    setStartingRoom: (id, cb) ->
        db.set "#{@worldKey}:startingRoom", id, cb

    getStartingRoom: (cb) ->
        db.get "#{@worldKey}:startingRoom", cb

    getRoomCount: (cb) ->
        db.scard "#{@worldKey}:rooms", (err, count) ->
            if err then cb err else cb null, parseInt(count, 10)

exports.World = World

class Player
    enterWorld: (world, cb) ->
        world.getStartingRoom (err, id) =>
            if err then return cb err
            @loc = id
            @world = world
            cb null

    getRoom: (cb) ->
        @world.getRoom @loc, cb

exports.Player = Player
