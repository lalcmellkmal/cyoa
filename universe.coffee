Backbone = require 'backbone'
_ = require 'underscore'
redis = require 'redis'
async = require 'async'

redisClient = ->
    require('redis').createClient()

db = redisClient()

class Universe
    constructor: ->
        @objs = {}
        @creating = {}

    connect: (cb) ->
        @sub = redisClient()
        @sub.psubscribe '*'
        @sub.once 'psubscribe', =>
            @sub.on 'message', @onMessage
            cb null

    onMessage: (pat, chan, msg) ->
        console.log pat, chan, msg
        obj = @objs[chan]
        if obj
            console.log 'obj', obj, 'triggered.'

    get: (cls, id, cb) ->
        prefix = cls.prototype.key
        if not prefix
            throw new Error "Invalid model #{cls}"
        name = "#{prefix}:#{id}"
        obj = @objs[name]
        if obj
            cb null, obj
        else if name of @creating
            @creating[name].push cb
        else
            waiting = []
            @creating[name] = waiting
            db.hgetall name, (err, attrs) =>
                notify = (err, obj) =>
                    delete @creating[name]
                    cb err, (obj or null)
                    if waiting.length
                        for otherCb in waiting
                            otherCb err, obj
                if err
                    notify err
                else if _.isEmpty attrs
                    notify 'Not found'
                else
                    @construct cls, name, attrs, (err, obj) =>
                        if err then return notify err
                        obj.id = id
                        @objs[name] = obj
                        notify null, obj

    create: (cls, cb) ->
        db.incr 'objCtr', (err, id) =>
            if err then return cb err
            obj = new cls
            obj.id = id
            cb null, obj

    construct: (cls, name, attrs, cb) ->
        schema = cls.prototype.schema
        if not schema
            throw new Error "Model #{cls} has no schema"
        obj = new cls
        waits = 0
        done = 0
        gotField = () ->
            done += 1
            if done == waits
                cb null, obj
        # Load it up!
        for k, kind of schema
            if kind is Object
                if k of attrs
                    try
                        obj[k] = JSON.parse attrs[k]
                    catch e
                        cb err
                        waits += 1 # ensure defered cb never succeeds
                        return
            else if kind.map
                waits += 1
                do (k) ->
                    db.hgetall "#{name}:#{k}", (err, bits) ->
                        if err
                            # Interrupt early
                            cb err
                        else
                            obj[k] = bits
                            gotField()
            else
                throw new Error "Bad schema spec: #{kind}"
        if not waits
            cb null, obj

_.extend Universe, Backbone.Events

U = new Universe
exports.U = U

class Model extends Backbone.Model

map = (mapping) ->
    if Object.keys(mapping).length != 1
        throw new Error 'Mapping must have one element'
    {map: mapping}

class Room extends Model
    key: "room"
    schema: {
        vis: Object
        exits: map(str: Room)
    }

    toJSON: ->
        return {vis: @vis, exits: @exits}

U.get Room, 1, (err, room) ->
    if err then throw err
    console.log 'loaded', JSON.stringify(room)

class World extends Backbone.Model
    constructor: (rooms) ->
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
