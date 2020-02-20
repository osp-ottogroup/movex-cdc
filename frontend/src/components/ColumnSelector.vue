<template>
  <div>
    <column-table :columns="columns"></column-table>
  </div>
</template>

<script>
import ColumnTable from './ColumnTable.vue';

export default {
  name: 'ColumnSelector',
  components: {
    ColumnTable,
  },
  props: {
    table: { type: Object, default: () => {} },
  },
  data() {
    return {
      columns: [],
    };
  },
};
</script>
