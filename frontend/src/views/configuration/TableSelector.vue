<template>
  <div>
    <table-table :tables="tables"></table-table>
    <button class="button" @click="isTableModalActive = true">Add Table</button>
    <table-modal :isActive.sync="isTableModalActive" :tables="dbTables"
                 @add-table="onAddTable"></table-modal>
  </div>
</template>

<script>
import TableTable from './TableTable.vue';
import TableModal from './TableModal.vue';

export default {
  name: 'TableSelector',
  components: {
    TableTable,
    TableModal,
  },
  props: {
    tables: { type: Array, default: () => [] },
    dbTables: { type: Array, default: () => [] },
  },
  data() {
    return {
      isTableModalActive: false,
    };
  },
  methods: {
    onAddTable(table) {
      console.log('onAddTable', table);
      this.tables.push(table);
      this.isTableModalActive = false;
    },
  },
};
</script>
