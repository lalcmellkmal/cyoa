var config = require('./config'),
    http = require('http'),
    fs = require('fs'),
    universe = require('./universe');

function plural(word, count) {
    return parseInt(count, 10) == 1 ? word : word + 's';
}

var world = new universe.World(1);

function setup(cb) {
    count <- world.getRoomCount();
    if (!count) {
        id <- world.allocRoom();
        _ <- world.createRoom(id, {vis: {desc: "You are at home."}});
        _ <- world.setStartingRoom(id);
        return "Made initial room.";
    }
    else {
        return "World has " + count + " " + plural('room', count);
    }
}

setup(function (err, msg) {
    if (err) throw err;
    console.log(msg);
});

var dirOpposites = {north: 'south', south: 'north', west: 'east', east: 'west', up: 'down', down: 'up'};

function execute(query, player, cb) {
    switch (query.verb) {
        case 'go':
        {
            var dir = query.arg.dir;
            room <- player.getRoom();
            if (room.exits && dir in room.exits) {
                var newLoc = room.exits[dir];
                if (newLoc) {
                    newRoom <- world.getRoom(newLoc);
                    player.loc = newLoc;
                    return look(newRoom);
                }
                else {
                    console.error("Missing destination for", dir);
                    return "You can't go that way.";
                }
            }
            else
                return "You can't go that way.";
        }

        case 'dig':
        {
            var dir = query.arg.dir, backDir = dirOpposites[dir];
            if (!dir || !backDir)
                return "That's not a direction.";
            var oldId = player.loc;
            oldRoom <- world.getRoom(oldId);
            if (!oldRoom.exits)
                oldRoom.exits = {};
            if (dir in oldRoom.exits)
                return "That's already an exit.";
            id <- world.allocRoom();
            var newRoom = {exits: {}};
            newRoom.exits[backDir] = oldId;
            _ <- world.createRoom(id, newRoom);
            oldRoom.exits[dir] = id;
            _ <- world.updateRoom(oldId, 'exits', oldRoom.exits);
            player.loc = id;
            var msg = look(newRoom);
            msg.prefix = 'Dug.';
            return msg;
        }

        case 'desc':
        {
            var newDesc = query.arg.desc.slice(0, 140);
            room <- player.getRoom();
            if (!room.vis)
                room.vis = {};
            room.vis.desc = newDesc;
            _ <- world.updateRoom(player.loc, 'vis', room.vis);
            var msg = look(room);
            msg.prefix = 'Changed.'
            return msg;
        }

        case 'look':
        {
            room <- player.getRoom();
            return look(room);
        }
 
        default:
            cb(null, "What?");
    }
}

function look(room) {
    var vis = {};
    vis.msg = (room.vis && room.vis.desc) || "Can't see shit captain.";
    if (room.exits)
        vis.exits = Object.keys(room.exits);
    return vis;
}

function doCommand(player, command, callback) {
    if (typeof command != 'object')
        return callback("Bad command.");

    try {
        execute(command, player, function (err, msg) {
            if (err) {
                dumpError(err, command, player);
                return callback('Game error.');
            }
            if (typeof msg == 'string')
                msg = {msg: msg};
            callback(null, msg);
        });
    }
    catch (e) {
        dumpError(e, command, player);
        callback('Server error.');
    }
}

function dumpError(error, command, player) {
    console.error((player ? 'Player #' + player.id : 'Unknown player') + " using command:");
    console.error(JSON.stringify(command));
    console.error("caused error:");
    console.error(error.stack || error);
}

/* WEB STUFF */

function handler(req, resp) {
    // TEMP debug
    if (config.DEBUG) {
        var name = req.url.slice(1);
        if (name == '') {
            resp.writeHead(200, {'Content-Type': 'text/html; charset=UTF-8'});
            fs.readFile('index.html', function (err, html) {
                if (err) throw err;
                resp.end(html);
            });
            return;
        }
        else if (media.indexOf(name) >= 0) {
            var mime = name.match(/\.js$/) ? 'application/javascript' : 'text/css';
            resp.writeHead(200, {'Content-Type': mime});
            var filename = req.url.slice(1);
            if (filename == 'client.js')
                filename = 'out/client.js';
            fs.readFile(filename, function (err, data) {
                if (err) throw err;
                resp.end(data);
            });
            return;
        }
        else {
            console.warn('No /' + name);
        }
    }
    resp.writeHead(404);
    resp.end('Not found');
}

var media = ['client.js', 'plain.css', 'jquery-1.7.1.min.js', 'input.js'];

var server = http.createServer(handler);
server.listen(config.PORT);

var io = require('socket.io').listen(server);
var CLIENTS = {};

io.configure(function () {
    io.set('authorization', function (handshake, callback) {
        var cookie = handshake.headers.cookie;
        // TODO
        callback(null, true);
    });
});

function onCommand(client, command) {
    doCommand(client.player, command, function (err, result) {
        if (err)
            client.socket.emit('error', err);
        else
            client.socket.emit('result', result);
    });
}

function onLogin(info) {
    if (!info.id || typeof info.id != 'string' || !info.id.match(/^\d+$/))
        return this.emit('error', 'Bad id.');
    var client = CLIENTS[info.id];
    if (!client)
        CLIENTS[info.id] = client = {id: info.id};
    if (client.socket) {
        client.socket.emit('error', 'Kicked out by another browser session.');
        client.socket.disconnect();
    }
    client.socket = this;

    if (!client.player) {
        var player = new universe.Player;
        player.enterWorld(world, function (err) {
            if (err) {
                console.error(err);
                client.emit('error', "Couldn't enter world.");
            }
            else if (client.player) {
                // Shouldn't happen due to .once()
                client.emit('error', 'Login conflict.');
            }
            else {
                client.player = player;
                ready('Welcome.');
            }
        });
    }
    else
        ready('Welcome back.');

    function ready(welcome) {
        client.socket.emit('login', {msg: welcome});
        client.socket.on('command', onCommand.bind(null, client));
    }
}

io.sockets.on('connection', function (socket) {
    socket.once('login', onLogin.bind(socket));
});

// vi: set sw=4 ts=4 sts=4 ai et filetype=javascript:
