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
        if not cb
            throw new Error "No get callback"
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
                    notify "#{name} not found"
                else
                    @construct cls, name, attrs, (err, obj) =>
                        if err then return notify err
                        obj.set id: id
                        @objs[name] = obj
                        notify null, obj

    create: (cls, cb) ->
        db.incr 'objCtr', (err, id) =>
            if err then return cb err
            obj = new cls
            obj.id = id
            # Defaults
            toSet = {}
            for k, kind of cls.prototype.schema
                if kind.map
                    toSet[k] = {}
            obj.set toSet
            cb null, obj

    construct: (cls, name, attrs, cb) ->
        schema = cls.prototype.schema
        if not schema
            throw new Error "Model #{cls} has no schema"
        obj = new cls
        waits = 0
        done = 0
        toSet = {}
        gotField = () ->
            done += 1
            if done == waits
                obj.set toSet
                cb null, obj
        # Load it up!
        for k, kind of schema
            if kind is Object
                if k of attrs
                    try
                        toSet[k] = JSON.parse attrs[k]
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
                            toSet[k] = bits
                            gotField()
            else
                throw new Error "Bad schema spec: #{kind}"
        if not waits
            obj.set toSet
            cb null, obj

    begin: ->
        new Transaction()

_.extend Universe, Backbone.Events

U = new Universe
exports.U = U

class Transaction
    constructor: ->
        @m = db.multi()

    save: (cls, obj) ->
        flat = {mod: new Date().getTime()}
        name = "#{cls.prototype.key}:#{obj.id}"
        m = @m
        for k, kind of cls.prototype.schema
            if kind is Object
                if obj.has k
                    flat[k] = JSON.stringify obj.get k
            else if kind.map
                key = "#{name}:#{k}"
                m.del key
                v = obj.get k
                if not _.isEmpty v
                    m.hmset key, v
        m.del name
        m.hmset name, flat

    end: (cb) ->
        @m.exec cb

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
exports.Room = Room

test = ->
    U.get Room, 1, (err, room) ->
        if err then throw err
        console.log 'loaded', JSON.stringify room

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

exports.addSimpleRooms = (cb) ->
    U.create Room, (err, room) ->
        if err then return cb err
        room.set {vis: {desc: 'You are at home.'}}
        m = U.begin()
        m.save Room, room
        console.log "Made room #{room.id}"
        m.end cb
