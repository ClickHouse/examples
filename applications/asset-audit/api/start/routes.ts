import router from '@adonisjs/core/services/router'
import app from '@adonisjs/core/services/app'
const StocktakesController = () => import('#controllers/stocktakes_controller')
router.get('/', ({ response }) => response.download(app.publicPath('index.html')))
router.get('/api/stocktakes', [StocktakesController, 'index'])
router.get('/api/stocktakes/:id', [StocktakesController, 'show'])
router.put('/api/stocktakes/:id', [StocktakesController, 'update'])
router.post('/api/stocktakes/:id/finalize', [StocktakesController, 'finalize'])
