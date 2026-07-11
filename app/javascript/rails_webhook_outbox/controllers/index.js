import { application } from "rails_webhook_outbox/controllers/application"
import SecretController from "rails_webhook_outbox/controllers/secret_controller"

application.register("secret", SecretController)
