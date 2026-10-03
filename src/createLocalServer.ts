import { LocalServer } from './customServer'

const { createMCServer } = require('flying-squid/dist')
// BlockMash world generator + gameplay plugins
require('flying-squid/dist/lib/generations').blockmash = require('./mashup/generator')
const installBlockMash = require('./mashup/serverPlugin')

export const startLocalServer = (serverOptions) => {
  const passOptions = { ...serverOptions, Server: LocalServer }
  const server: NonNullable<typeof localServer> = createMCServer(passOptions)
  server.formatMessage = (message) => `[server] ${message}`
  server.options = passOptions
  //@ts-expect-error todo remove
  server.looseProtocolMode = true
  if (passOptions.generation?.name === 'blockmash' || !passOptions.generation) installBlockMash(server)
  return server
}

// features that flying-squid doesn't support at all
// todo move & generate in flying-squid
export const unsupportedLocalServerFeatures = ['transactionPacketExists', 'teleportUsesOwnPacket']
