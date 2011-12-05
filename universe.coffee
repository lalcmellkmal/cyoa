Backbone = require 'backbone'

class World extends Backbone.Model
    initialize: (rooms) ->
        @set rooms

class Player extends Backbone.Model
    initialize: ->
        @set loc: 'home'
exports.Player = Player

world = new World
    room_home:
        desc: 'You are at home.'
        exits: {north: 'porch'}
    room_porch:
        desc: 'You are on the porch.'
        exits: {south: 'home'}

exports.world = world
