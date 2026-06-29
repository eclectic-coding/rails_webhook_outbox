class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.string :title, null: false
      t.decimal :total, null: false, precision: 10, scale: 2
      t.string :status, null: false, default: "pending"
      t.datetime :cancelled_at

      t.timestamps
    end
  end
end