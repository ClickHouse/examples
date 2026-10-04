import { bootstrapApplication } from '@angular/platform-browser'
import { provideHttpClient } from '@angular/common/http'
import { providePrimeNG } from 'primeng/config'
import Aura from '@primeuix/themes/aura'
import { AppComponent } from './app'
bootstrapApplication(AppComponent, {
  providers: [provideHttpClient(), providePrimeNG({ theme: { preset: Aura, options: { darkModeSelector: '.dark-mode' } } })],
}).catch(console.error)
