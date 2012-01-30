var _ = require('underscore'),
    config = require('./config'),
    redis = require('redis');

function redisClient() {
	return redis.createClient(config.REDIS_PORT);
}

var db = redisClient();

function World(worldIndex) {
	this.worldKey = "world:" + worldIndex;
}
var W = World.prototype;

W.allocRoom = function (cb) {
	id <- db.incr('roomCtr');
	return id;
};

W.createRoom = function (id, room, cb) {
	var key = "room:" + id;
	exists <- db.exists(key);
	if (exists)
		throw "Room " + id + " already exists!";
	var info = {};
	for (var k in room)
		info[k] = JSON.stringify(room[k]);
	var m = db.multi();
	m.hmset(key, info);
	m.sadd(this.worldKey + ":rooms", id);
	m.exec(cb);
};


W.updateRoom = function (id, k, v, cb) {
	var key = "room:" + id;
	exists <- db.exists(key);
	if (!exists)
		throw "No room " + id;
	db.hset(key, k, JSON.stringify(v), cb);
};

W.getRoom = function (id, cb) {
	info <- db.hgetall("room:" + id);
	if (_.isEmpty(info))
		throw "No such room.";
	var room = {};
	try {
		for (var k in info)
			room[k] = JSON.parse(info[k]);
	}
	catch (e) {
		cb(e);
		return;
	}
	return room;
};

W.setStartingRoom = function (id, cb) {
	db.set(this.worldKey + ":startingRoom", id, cb);
};

W.getStartingRoom = function (cb) {
	db.get(this.worldKey + ":startingRoom", cb);
};

W.getRoomCount = function (cb) {
	count <- db.scard(this.worldKey + ":rooms");
	return parseInt(count, 10);
};

exports.World = World;

function Player() {
}
var P = Player.prototype;

P.enterWorld = function (world, cb) {
	id <- world.getStartingRoom();
	this.loc = id;
	this.world = world;
	return true;
};

P.getRoom = function (cb) {
	this.world.getRoom(this.loc, cb);
};

exports.Player = Player;
