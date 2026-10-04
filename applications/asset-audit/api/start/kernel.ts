import router from '@adonisjs/core/services/router'
import server from '@adonisjs/core/services/server'
server.use([() => import('#middleware/local_operator_middleware'), () => import('@adonisjs/static/static_middleware')])
router.use([() => import('@adonisjs/core/bodyparser_middleware')])
