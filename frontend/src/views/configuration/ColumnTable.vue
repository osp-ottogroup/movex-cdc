<template>
  <div>
    <table class="table is-striped is-hoverable">
      <thead>
      <tr>
        <th>
          Name
        </th>
        <th>
          Insert-Trigger
        </th>
        <th>
          Update-Trigger
        </th>
        <th>
          Delete-Trigger
        </th>
      </tr>
      </thead>
      <tbody>
      <tr v-for="column in columns" :key="column.id">
        <td>{{ column.name }}</td>
        <td>
          <input type="checkbox"
                 :checked="column.yn_log_insert === 'Y'"
                 @change="onColumnChanged('insert', column)"
          >
        </td>
        <td>
          <input type="checkbox"
                 :checked="column.yn_log_update === 'Y'"
                 @change="onColumnChanged('update', column)">
        </td>
        <td>
          <input type="checkbox"
                 :checked="column.yn_log_delete === 'Y'"
                 @change="onColumnChanged('delete', column)">
        </td>
      </tr>
      </tbody>
    </table>
  </div>
</template>

<script>
export default {
  name: 'ColumnTable',
  props: {
    columns: { type: Array, default: () => [] },
  },
  methods: {
    onColumnChanged(type, column) {
      switch (type) {
        case 'insert': column.yn_log_insert = this.yesNoToggle(column.yn_log_insert); break; // eslint-disable-line no-param-reassign
        case 'update': column.yn_log_update = this.yesNoToggle(column.yn_log_update); break; // eslint-disable-line no-param-reassign
        case 'delete': column.yn_log_delete = this.yesNoToggle(column.yn_log_delete); break; // eslint-disable-line no-param-reassign
        default: throw new Error(`Type '${type}' is not supported`);
      }
      this.$emit('column-changed', column);
    },
    yesNoToggle(value) {
      let toggle;
      if (value === 'Y') {
        toggle = 'N';
      } else {
        toggle = 'Y';
      }
      return toggle;
    },
  },
};
</script>
