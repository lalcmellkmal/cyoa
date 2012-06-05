var _ = require('underscore'),
    config = require('./config'),
    lua = require('./lua'),
    redis = require('redis');

function redisClient() {
	return redis.createClient(config.REDIS_PORT);
}
exports.redisClient = redisClient;

var db = redisClient();
lua.setDb(db);

function World(worldIndex) {
	this.worldKey = "world:" + worldIndex;
}
var W = World.prototype;

var luaMakeRoom = lua.LuaScript("""
	local id = redis.call('incr', 'roomCtr')
	local key = 'room:'..id
	if redis.call('exists', key) ~= 0 then
		return {err="Room "..id.." already exists!"}
	end
	redis.call('hmset', key, JSONHASH[1])
	redis.call('sadd', KEYS[1], id)
	return id
""");

W.createRoom = function (room, cb) {
	room.created = new Date().getTime();
	luaMakeRoom.eval({}, [this.worldKey + ':rooms'], [room], cb);
};

W.updateRoom = function (id, k, v, cb) {
	var key = "room:" + id;
	exists <- db.exists(key);
	if (!exists)
		throw "No room " + id;
	db.hset(key, k, JSON.stringify(v), cb);
};

W.getRoom = function (id, cb) {
	var m = db.multi();
	var key = "room:" + id;
	m.hgetall(key);
	m.smembers(key + ":players");
	m.hgetall(key + ':exits');
	rs <- m.exec();
	var info = rs[0], players = rs[1], exits = rs[2];
	if (!info || _.isEmpty(info))
		throw "No such room " + id + ".";
	var room = {};
	try {
		for (var k in info)
			room[k] = JSON.parse(info[k]);
	}
	catch (e) {
		console.error(e);
		throw "Corrupt room.";
	}
	room.players = players || [];
	if (exits)
		room.exits = exits;
	return room;
};

W.lookupRoomExit = function (id, dir, cb) {
	dest <- db.hget('room:' + id + ':exits', dir);
	return dest;
};

W.addRoomExit = function (id, dir, cb) {
	wasSet <- db.hsetnx('room:' + id + ':exits', dir, '0');
	if (!wasSet)
		throw "Exit already exists.";
	return null;
};

W.setRoomExit = function (id, dir, dest, cb) {
	_ <- db.hset('room:' + id + ':exits', dir, dest);
	return null;
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
	var m = db.multi();
	m.set('player:' + playerId + ':loc', roomId);
	m.sadd('room:' + roomId + ':players', playerId);
	_ <- m.exec();
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

P.move = function (oldRoom, newRoom, dir, cb) {
	luaMovePlayer.eval({oldRoom: oldRoom, newRoom: newRoom, player: this.id, dir: dir}, function (err) {
		if (err && err.message.match(/BADEXIT/))
			cb("You can't go that way.");
		else if (err && err.message.match(/WRONGSRC/))
			cb("Not in the same room anymore.");
		else
			cb(err);
	});
};

var luaMovePlayer = lua.LuaScript("""
	if redis.call('get', K[player:loc]) ~= A[oldRoom] then
		return {err="WRONGSRC"}
	end
	local dest = redis.call('hget', K[oldRoom:exits], A[dir])
	if not dest or dest ~= A[newRoom] then
		return {err="BADEXIT"}
	end
	if redis.call('exists', K[newRoom]) ~= 1 then
		return {err="BADEXIT"}
	end
	if redis.call('smove', K[oldRoom:players], K[newRoom:players], A[player]) == 0 then
		return {err="WRONGSRC"}
	end
	redis.call('set', K[player:loc], dest)
	return dest
""");

exports.Player = Player;
