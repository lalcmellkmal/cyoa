var _ = require('underscore'),
    config = require('./config'),
    crypto = require('crypto'),
    redis = require('redis');

function redisClient() {
	return redis.createClient(config.REDIS_PORT);
}
exports.redisClient = redisClient;

var db = redisClient();

function World(worldIndex) {
	this.worldKey = "world:" + worldIndex;
}
var W = World.prototype;

function LuaScript(src) {
	if (!(this instanceof LuaScript))
		return new LuaScript(src);
	this.src = this.convertLookups(this.transformSource(src));
	this.sha = crypto.createHash('sha1').update(src).digest('hex');
}

LuaScript.prototype.transformSource = function (src) {
	this.modifiers = {};
	var keyCount = 0, argCount = 0;
	var result = [];
	var bits = src.split(/(KEYS|ARGV|JSONHASH)\[(\d+)\]/g);
	for (var i = 0; i < bits.length; i++) {
		if (i % 3 == 0) {
			result.push(bits[i]);
			continue;
		}
		var kind = bits[i];
		var index = parseInt(bits[++i], 10);
		var transformed = null;
		if (kind == 'KEYS')
			keyCount = Math.max(keyCount, index);
		else {
			argCount = Math.max(argCount, index);
			if (kind == 'JSONHASH') {
				transformed = 'unpack(cjson.decode(ARGV[' + index + ']))';
				this.modifiers[index] = stringifyValues;
			}
		}
		result.push(transformed || (kind + '[' + index + ']'));
	}
	this.keyCount = keyCount;
	this.argCount = argCount;
	src = result.join('');
	src = src.replace(/DEBUG\(/g, 'redis.log(redis.LOG_WARNING, ');
	return src;
};

LuaScript.prototype.convertLookups = function (src) {
	this.extraKeys = [];
	this.extraArgs = [];
	var keyIndices = {}, argIndices = {};
	var result = [];
	var bits = src.split(/([KA])\[([\w:]+)\]/g);
	for (var i = 0; i < bits.length; i++) {
		if (i % 3 == 0) {
			result.push(bits[i]);
			continue;
		}
		var kind = bits[i];
		var fullKey = bits[++i];

		var transformed;
		if (kind == 'K') {
			var index = keyIndices[fullKey];
			if (!index) {
				var parts = fullKey.match(/^(\w+)(:.+)?$/);
				var info = {stem: parts[1], tail: parts[2] || ''};
				var m = info.stem.match(/[A-Z][a-z]*$/);
				info.noun = m ? m[0].toLowerCase() : info.stem;
				this.extraKeys.push(info);
				var index = this.keyCount + this.extraKeys.length;
				keyIndices[fullKey] = index;
			}
			transformed = 'KEYS[' + index + ']';
		}
		else if (kind == 'A') {
			var index = argIndices[fullKey];
			if (!index) {
				this.extraArgs.push(fullKey);
				var index = this.argCount + this.extraArgs.length;
				argIndices[fullKey] = index;
			}
			transformed = 'ARGV[' + index + ']';
		}
		result.push(transformed);
	}
	return result.join('');
};

LuaScript.prototype.eval = function (keywords, keys, args, callback) {
	if (!callback) {
		callback = args;
		args = [];
	}
	if (!callback) {
		callback = keys;
		keys = [];
	}
	var self = this;

	var n = this.keyCount;
	if (keys.length != n)
		throw "Ought to have " + n + " key(s): " + keys;
	if (args.length != this.argCount)
		throw "Ought to have " + this.argCount + " arg(s): " + args;

	/* Insert keyword arguments */
	var allArgs = keys.slice();
	n += this.extraKeys.length;
	this.extraKeys.forEach(function (keyInfo) {
		if (!(keyInfo.stem in keywords))
			throw "Keyword missing: " + keyInfo.stem;
		allArgs.push(keyInfo.noun + ':' + keywords[keyInfo.stem] + keyInfo.tail);
	});
	/* Massage values according to previous spec */
	args.forEach(function (val, i) {
		var func = self.modifiers[i + 1];
		allArgs.push((func ? func(val) : val).toString());
	});
	this.extraArgs.forEach(function (keyword) {
		if (!(keyword in keywords))
			throw "Argument missing: " + keyword;
		allArgs.push(keywords[keyword].toString());
	});

	db.evalsha(this.sha, n, allArgs.slice(), function (err, result) {
		/* Gah, this sucks. Any way to get the redis error name? */
		if (err && err.message.match(/NOSCRIPT/))
			db.eval(self.src, n, allArgs, callback);
		else if (err)
			callback(err);
		else
			callback(null, result);
	});
};

var luaMakeRoom = LuaScript("""
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
	luaMakeRoom.eval({}, [this.worldKey + ':rooms'], [room], cb);
};

function stringifyValues(obj) {
	var results = [];
	for (var k in obj)
		results.push(k, JSON.stringify(obj[k]));
	return JSON.stringify(results);
}

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
	rs <- m.exec();
	var info = rs[0], players = rs[1];
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

P.move = function (oldRoom, newRoom, cb) {
	luaMovePlayer.eval({oldRoom: oldRoom, newRoom: newRoom, player: this.id}, function (err) {
		if (err && err.message.match(/WRONGSRC/))
			cb("Not in the same room anymore.");
		else
			cb(err);
	});
};

var luaMovePlayer = LuaScript("""
	if redis.call('get', K[player:loc]) ~= A[oldRoom] then
		return {err="WRONGSRC"}
	end
	if redis.call('smove', K[oldRoom:players], K[newRoom:players], A[player]) == 0 then
		return {err="WRONGSRC"}
	end
	redis.call('set', K[player:loc], A[newRoom]);
""");

exports.Player = Player;
