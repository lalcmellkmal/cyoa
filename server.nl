var config = require('./config'),
    connect = require('connect'),
    fs = require('fs'),
    universe = require('./universe');

var players = {};

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
            break;

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
            break;

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
            break;

        case 'look':
        {
            room <- player.getRoom();
            return look(room);
        }
            break;
 
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

function handler(req, resp) {
    if (req.method == 'POST') {
        var query = req.body.q, user = req.body.u;
        var result = null;
        function reply(packet) {
            resp.writeHead(200, {'Content-Type': 'application/json'});
            resp.end(JSON.stringify(packet));
        }
        if (!user)
            reply({error: 'No login.'});
        else if (typeof query != 'object')
            reply({error: 'Bad query.'});
        else {
            function doIt(player, prefix) {
                try {
                    execute(query, player, function (err, msg) {
                        if (err) {
                            reply({error: 'Game error.'});
                            console.error(err.stack || err);
                        }
                        else {
                            if (typeof msg == 'string')
                                msg = {msg: msg};
                            if (prefix)
                                msg.prefix = prefix;
                            reply(msg);
                        }
                    });
                }
                catch (e) {
                    console.error(e.stack);
                    reply({error: 'Server error.'});
                }
            }

            if (user in players) {
                doIt(players[user], '');
            }
            else {
                var player = new universe.Player;
                player.enterWorld(world, function (err) {
                    if (err) {
                        console.error(err);
                        reply({error: "Couldn't enter world."});
                    }
                    else {
                        players[user] = player;
                        doIt(player, 'Welcome. ');
                    }
                });
            }
        }
        return;
    }

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
            fs.readFile(req.url.slice(1), function (err, data) {
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

var server = connect.createServer(connect.bodyParser(), handler);
server.listen(config.PORT);

// vi: set sw=4 ts=4 sts=4 ai et filetype=javascript:
