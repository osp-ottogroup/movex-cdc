<template>
  <div class="container">
    <b-tabs @input="onTabChanged">
      <b-tab-item label="Instance" :value="tabNames.INSTANCE">
        <p v-for="element in instanceData" :key="element.name" class="columns">
          <span class="column">{{ element.name }}</span>
          <span class="column">{{ element.value }}</span>
        </p>
      </b-tab-item>

      <b-tab-item label="Health" :value="tabNames.HEALTH">
        <pre>{{ healthCheck }}</pre>
      </b-tab-item>

      <b-tab-item label="Kafka Topics" :value="tabNames.KAFKA_TOPICS">
        <b-field>
          <b-select placeholder="Select a topic" @input="onTopicSelected" :loading="isLoading">
            <option v-for="topic in topics" :key="topic" :value="topic">{{ topic }}</option>
          </b-select>
        </b-field>
        <div>
          <pre v-if="topicDetails">{{ formattedTopicDetails }}</pre>
        </div>
      </b-tab-item>

      <b-tab-item label="Kafka Groups" :value="tabNames.KAFKA_GROUPS">
        <b-field>
          <b-select placeholder="Select a group" @input="onGroupSelected" :loading="isLoading">
            <option v-for="group in groups" :key="group" :value="group">{{ group }}</option>
          </b-select>
        </b-field>
        <div>
          <pre v-if="groupDetails">{{ formattedGroupDetails }}</pre>
        </div>
      </b-tab-item>
    </b-tabs>
  </div>
</template>

<script>
import CRUDService from '@/services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';

export default {
  name: 'InstanceInfos',
  data() {
    return {
      tabNames: {
        INSTANCE: 'INSTANCE',
        HEALTH: 'HEALTH',
        KAFKA_TOPICS: 'KAFKA_TOPICS',
        KAFKA_GROUPS: 'KAFKA_GROUPS',
      },
      instanceData: [],
      healthCheck: '',
      topics: [],
      groups: [],
      topicDetails: null,
      groupDetails: null,
      isLoading: true,
    };
  },
  async created() {
    try {
      // load only the data of the first tab (which is instance information)
      await this.loadInstanceData();
    } catch (e) {
      this.$buefy.notification.open({
        message: getErrorMessageAsHtml(e, 'An error occurred while loading instance infos!'),
        type: 'is-danger',
        indefinite: true,
        position: 'is-top',
      });
    } finally {
      this.isLoading = false;
    }
  },
  computed: {
    formattedTopicDetails() {
      return JSON.stringify(this.topicDetails, null, 4);
    },
    formattedGroupDetails() {
      return JSON.stringify(this.groupDetails, null, 4);
    },
  },
  methods: {
    async onTopicSelected(topic) {
      try {
        this.isLoading = true;
        this.topicDetails = null;
        this.topicDetails = await CRUDService.kafka.topics.get({ topic });
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e, 'An error occurred while loading topic details!'),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
    async onGroupSelected(group) {
      try {
        this.isLoading = true;
        this.groupDetails = null;
        this.groupDetails = await CRUDService.kafka.groups.get({ group_id: group });
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e, 'An error occurred while loading group details!'),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
    async loadHealthData() {
      this.healthCheck = await CRUDService.healthCheck.check();
    },
    async loadInstanceData() {
      this.instanceData = (await CRUDService.instance.info()).config_info;
    },
    async loadKafkaTopicsData() {
      this.topics = (await CRUDService.kafka.topics.getAll()).topics;
    },
    async loadKafkaGroupsData() {
      this.groups = (await CRUDService.kafka.groups.getAll()).groups;
    },
    async onTabChanged(value) {
      try {
        this.isLoading = true;
        switch (value) {
          case this.tabNames.HEALTH:
            await this.loadHealthData();
            break;
          case this.tabNames.INSTANCE:
            await this.loadInstanceData();
            break;
          case this.tabNames.KAFKA_TOPICS:
            await this.loadKafkaTopicsData();
            break;
          case this.tabNames.KAFKA_GROUPS:
            await this.loadKafkaGroupsData();
            break;
          default:
            throw new Error(`tab value ${value} is unknown`);
        }
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e, 'An error occurred while loading tab data!'),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
  },
};
</script>
