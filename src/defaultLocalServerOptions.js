module.exports = {
  'motd': 'BlockMash',
  // host: '',
  // eslint-disable-next-line unicorn/numeric-separators-style
  'port': 25565,
  'max-players': 10,
  'online-mode': false,
  'gameMode': 0,
  'difficulty': 0,
  'worldFolder': 'world',
  // todo set sid, disable entities auto-spawn
  'generation': {
    // grass_field
    // diamond_square
    // empty
    // superflat
    // all_the_blocks
    // nether
    'name': 'blockmash',
    options: {}
    // 'options': {
    //   'worldHeight': 80
    // }
  },
  'kickTimeout': 10_000,
  'plugins': {},
  'modpe': false,
  'view-distance': 2,
  'player-list-text': {
    'header': 'BlockMash',
    'footer': 'singleplayer'
  },
  keepAlive: false,
  'everybody-op': true,
  'max-entities': 400,
  'version': '1.14.4',
  versionMajor: '1.14'
}
