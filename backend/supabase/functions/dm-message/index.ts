import { handle } from '../_shared/messageActions.ts'

Deno.serve((req) => handle(req, { table: 'direct_messages', ownerColumn: 'sender_id', rateAction: 'dm_message',
  privilege: 'dm', maxLength: 2000 }))
