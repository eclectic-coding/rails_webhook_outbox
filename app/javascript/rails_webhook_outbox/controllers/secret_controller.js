import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "revealButton", "copiedHint"]
  static values  = { value: String }

  connect() {
    this.masked = this.displayTarget.textContent
    this.revealed = false
  }

  reveal() {
    this.revealed = !this.revealed
    this.displayTarget.textContent = this.revealed ? this.valueValue : this.masked
    this.revealButtonTarget.textContent = this.revealed ? "Hide" : "Reveal"
  }

  copy() {
    navigator.clipboard.writeText(this.valueValue).then(() => {
      this.copiedHintTarget.hidden = false
      setTimeout(() => { this.copiedHintTarget.hidden = true }, 1500)
    })
  }
}
