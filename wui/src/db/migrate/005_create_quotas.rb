class CreateQuotas < ActiveRecord::Migration
  def self.up
    create_table :quotas do |t|
      t.column :name,                       :string
      t.column :total_vcpus,                :integer
      t.column :total_vmemory,              :integer
      t.column :total_vnics,                :integer
      t.column :total_storage,              :integer
      t.column :total_vms,                  :integer
      t.column :hardware_pool_id,           :integer, :null => false
    end
    execute "alter table quotas add constraint fk_quotas_hw_pools
             foreign key (hardware_pool_id) references hardware_pools(id)"
  end

  def self.down
    drop_table :quotas
  end
end
