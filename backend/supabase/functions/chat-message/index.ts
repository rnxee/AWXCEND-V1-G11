import { handle } from '../_shared/messageActions.ts'

Deno.serve((req) => handle(req, { table: 'chat_messages', ownerColumn: 'user_id', rateAction: 'chat_message',
  privilege: 'chat', maxLength: 500 }))
