Backbone = require 'backbone'
redis = require 'redis'
async = require 'async'

class World extends Backbone.Model
    initialize: (rooms) ->
        @set rooms

class Player extends Backbone.Model
    initialize: ->
        @set loc: 1
exports.Player = Player

redisClient = ->
    redis.createClient()

exports.loadWorld = (cb) ->
    worldIndex = 1
    key = "world:#{worldIndex}"
    r = redisClient()
    r.smembers "#{key}:rooms", (err, roomNumbers) ->
        if err
            r.quit()
            cb err
        roomMap = {}
        count = 0
        loadRoom = (id, cb) ->
            r.hgetall "room:#{id}", (err, roomBlob) ->
                if err
                    return cb err
                room = {}
                for key, val of roomBlob
                    room[key] = JSON.parse val
                roomMap[id] = room
                count++
                cb null
        async.forEach roomNumbers, loadRoom, (err) ->
            r.quit()
            if err
                return cb err
            console.log "Loaded #{count} rooms."
            cb null, new World(roomMap), count

exports.addSimpleRooms = (world) ->
    world.set
        1: {vis: {desc: 'You are at home.'}, exits: {north: 2}}
        2: {vis: {desc: 'You are outside.'}, exits: {south: 1}}

exports.saveWorld = (world, cb) ->
    worldIndex = 1
    r = redisClient()
    m = r.multi()
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
        r.quit()
        if not err
            console.log "Saved #{count} rooms."
        cb err
