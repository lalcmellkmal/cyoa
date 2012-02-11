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
	if (!info || _.isEmpty(info))
		throw "No such room.";
	var room = {};
	try {
		for (var k in info)
			room[k] = JSON.parse(info[k]);
	}
	catch (e) {
		console.error(e);
		throw "Corrupt room.";
	}
	return room;
};

W.setStartingRoom = function (id, cb) {
	db.set(this.worldKey + ":startingRoom", id, cb);
};

W.getStartingRoom = function (cb) {
	loc <- db.get(this.worldKey + ":startingRoom");
	if (!loc)
		throw "No starting room?!";
	return loc;
};

W.getRoomCount = function (cb) {
	count <- db.scard(this.worldKey + ":rooms");
	return parseInt(count, 10);
};

exports.World = World;

function Player(id, world) {
	this.id = id;
	this.name = 'Guest-' + id;
	this.world = world;
}
var P = Player.prototype;

Player.getOrCreate = function (clientId, world, cb) {
	playerId <- db.hget('players:idMap', clientId);
	if (playerId)
		return new Player(playerId, world);
	playerId <- db.incr('players:idCtr');
	_ <- db.hset('players:idMap', clientId, playerId);

	roomId <- world.getStartingRoom();
	_ <- db.set('player:' + playerId + ':loc', roomId);
	return new Player(playerId, world);
};

P.getLoc = function (cb) {
	loc <- db.get('player:' + this.id + ':loc');
	return loc;
};

P.getRoom = function (cb) {
	loc <- this.getLoc();
	room <- this.world.getRoom(loc);
	return room;
};

P.setLoc = function (loc, cb) {
	_ <- db.set('player:' + this.id + ':loc', loc);
	return null;
};

exports.Player = Player;
